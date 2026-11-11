import XCTest

/// Walks the sample log through every screen, audits each one, and keeps a screenshot of it.
/// `docs/design.md` records what each exclusion rests on.
@MainActor
struct ScreenTour {
  let test: XCTestCase
  let prefix: String
  var language = "en"
  var textSize: String?
  /// The audits of a tour.
  /// The tours at the default contrast leave contrast to the tours that run with Increase Contrast, because the system draws secondary text below the required ratio by default.
  /// The accessibility guidance asks an app in that position to reach the required ratio when Increase Contrast is on.
  /// See https://developer.apple.com/design/human-interface-guidelines/accessibility.
  /// Only the tours at the largest text size audit clipped text, because the audit of a smaller size predicts what those tours observe.
  var audits: XCUIAccessibilityAuditType = .all.subtracting([.contrast, .textClipped])

  /// The localized name of the first starter exercise in each language.
  private static let benchPress = [
    "en": "Bench Press", "ja": "ベンチプレス", "zh-Hans": "卧推", "zh-Hant": "臥推",
  ]

  /// The Log tab's label in each language.
  private static let logTab = ["en": "Log", "ja": "記録", "zh-Hans": "记录", "zh-Hant": "紀錄"]

  /// The screens that show text without an accessibility element of its own, which the system draws.
  /// The set editor leaves the screen under its sheet visible, the day picker draws a calendar, and the charts draw axis labels.
  /// Each chart mark carries the value of its axis label as its spoken label.
  private static let systemText = [
    "03-set-editor", "05-day-picker", "06-analysis", "07-exercise-progress",
  ]

  private static let settingsText = [
    "open-exercises", "open-backup", "open-watch", "open-privacy", "open-shortcuts",
    "storage-heading", "storage-text", "app-version",
  ]

  private func visibleSettingsFrame(_ identifier: String, in app: XCUIApplication) -> CGRect {
    let element = app.any(identifier)
    for _ in 0..<12 {
      if element.exists {
        let frame = element.frame
        let viewport = CGRect(
          x: app.frame.minX, y: app.navigationBars.firstMatch.frame.maxY,
          width: app.frame.width,
          height: app.tabBars.firstMatch.frame.minY - app.navigationBars.firstMatch.frame.maxY)
        if frame.height > 0 && viewport.contains(frame) { return frame }
        if frame.minY < viewport.minY {
          app.swipeDown(velocity: .slow)
        } else {
          app.swipeUp(velocity: .slow)
        }
      } else {
        app.swipeUp(velocity: .slow)
      }
    }
    test.capture("\(prefix)-settings-bounds-\(identifier)")
    XCTFail("\(identifier) didn't fit fully between the navigation bar and the tab bar")
    return .zero
  }

  private func settingsReference() -> [String: CGRect] {
    guard textSize != nil else { return [:] }
    let app = Gymemo.launch(
      store: "settings-reference-\(prefix)", sample: true, tab: "settings",
      textSize: "UICTContentSizeCategoryL", language: language)
    return Dictionary(
      uniqueKeysWithValues: Self.settingsText.map {
        ($0, visibleSettingsFrame($0, in: app))
      })
  }

  private func checkSettingsGrowth(_ app: XCUIApplication, reference: [String: CGRect]) {
    guard textSize != nil else { return }
    for identifier in Self.settingsText {
      let frame = visibleSettingsFrame(identifier, in: app)
      XCTAssertGreaterThan(
        frame.height, reference[identifier]?.height ?? .infinity,
        "\(language): \(identifier) must grow with the largest text size")
    }
    app.swipeDown(velocity: .fast)
    app.swipeDown(velocity: .fast)
  }

  /// Whether the audit reports something that the app can't change.
  private func isSystemDrawn(
    _ issue: XCUIAccessibilityAuditIssue, on screen: String, in app: XCUIApplication,
    snapshot: PrivacyAuditSnapshot?
  ) -> Bool {
    // The audit reports partial support for the calendar of the date picker, which keeps one size, and for text in system styles inside a list.
    // Apple's Settings app gets the same report for its own title.
    // The source check refuses a fixed font size, and two tours run at the largest text size.
    if issue.auditType == .dynamicType { return issue.compactDescription.contains("partially") }
    guard let element = issue.element else {
      switch issue.auditType {
      // Neither the test nor Xcode can find the view behind a report without an element.
      // Apple's Settings app gets the same contrast reports, and their number stayed the same when this app exposed every text that it merges or hides.
      // The one report of clipped text came from a row that the list had scrolled halfway under the top bar.
      case .contrast, .textClipped: return true
      // Text without an element stays a failure outside the screens where the system draws such text.
      case .elementDetection:
        return Self.systemText.contains(String(screen.prefix(while: { $0 != "+" })))
      default: return false
      }
    }
    guard issue.auditType == .contrast || issue.auditType == .textClipped else { return false }
    let frame: CGRect
    if let snapshot {
      guard let captured = snapshot.frame(for: element) else { return false }
      frame = captured
    } else {
      frame = element.frame
    }
    // A bar floats over the content, and the audit measures the text under the bar through its material.
    if frame.maxY > (snapshot?.tabFrame ?? app.tabBars.firstMatch.frame).minY { return true }
    if let snapshot, frame.minY < snapshot.navigationFrame.maxY,
      !snapshot.navigationFrame.contains(frame)
    {
      return true
    }
    // The header of the set editor lies on the sheet's material under the sheet's bar.
    // A screenshot with Increase Contrast shows 5.5:1 between its text and its background.
    return element.identifier == "edit-exercise"
  }

  private func check(_ app: XCUIApplication, _ name: String) throws {
    test.capture("\(prefix)-\(name)")
    let snapshot = name.hasPrefix("12-privacy") ? try PrivacyAuditSnapshot(app) : nil
    try app.performAccessibilityAudit(for: audits) { issue in
      if passesMeasuredContrast(issue, on: name, in: app, snapshot: snapshot) { return true }
      if passesMeasuredPlaceholder(issue, on: name) { return true }
      if isSystemDrawn(issue, on: name, in: app, snapshot: snapshot) { return true }
      let element = issue.element.map { element in
        "type \(element.elementType.rawValue) identifier '\(element.identifier)' label '\(element.label)' frame \(element.frame)"
      }
      XCTFail(
        "\(prefix)-\(name): \(issue.compactDescription) on \(element ?? "no element"): \(issue.detailedDescription)"
      )
      return true
    }
  }

  private func passesMeasuredPlaceholder(
    _ issue: XCUIAccessibilityAuditIssue, on screen: String
  ) -> Bool {
    guard issue.auditType == .textClipped, language == "en",
      textSize == Gymemo.largestTextSize, screen == "01-log-empty-weight",
      let element = issue.element, element.elementType == .textField,
      element.identifier == "weight-Bench Press", element.placeholderValue == "Bodyweight",
      let value = element.value as? String, value.isEmpty || value == "Bodyweight"
    else { return false }
    let required = PlaceholderTextFit.requiredSize("Bodyweight")
    let available = element.frame.size
    XCTContext.runActivity(
      named: "Measured placeholder: \(required) within \(available)"
    ) { _ in }
    return PlaceholderTextFit.fits("Bodyweight", in: available)
  }

  private func passesMeasuredContrast(
    _ issue: XCUIAccessibilityAuditIssue, on screen: String, in app: XCUIApplication,
    snapshot: PrivacyAuditSnapshot?
  ) -> Bool {
    guard issue.auditType == .contrast, let element = issue.element else { return false }
    let editorLabel =
      screen == "03-set-editor"
      && ["label-edit-weight", "label-edit-reps", "unit-edit-weight", "label-delete-set"].contains(
        element.identifier)
    let privacyValue =
      screen.hasPrefix("12-privacy")
      && element.identifier == "privacy-collection-value"
    let privacyTitle =
      snapshot.map { captured in
        element.elementType == .staticText && element.label == captured.navigationTitle
          && captured.frame(for: element).map(captured.navigationFrame.contains) == true
      } ?? false
    guard editorLabel || privacyValue || privacyTitle else { return false }
    let measured =
      snapshot.map {
        $0.contrast(of: element, darkInk: privacyTitle ? !prefix.contains("dark") : nil)
      } ?? PrimaryTextContrast.measure(element, in: app)
    guard let ratio = measured else { return false }
    let name = element.identifier.isEmpty ? element.label : element.identifier
    XCTContext.runActivity(named: "Measured \(name) contrast: \(ratio):1") { _ in }
    return ratio >= 4.5
  }

  /// Checks the part of a screen that the largest text size pushes under the first screenful, then returns to the top.
  private func checkBelow(_ app: XCUIApplication, _ name: String) throws {
    guard textSize != nil else { return }
    app.swipeUp()
    try check(app, "\(name)+below")
    app.swipeDown(velocity: .fast)
    app.swipeDown(velocity: .fast)
  }

  func runPrivacy() throws {
    let app = Gymemo.launch(
      store: "privacy-\(prefix)", tab: "settings", textSize: textSize, language: language)
    app.buttons["open-privacy"].scrollAndTap(in: app)
    try PrivacyTour.read(in: app) { page in
      try check(app, page == 0 ? "12-privacy" : "12-privacy+\(page)")
    }
  }

  func runSettings() throws {
    let reference = settingsReference()
    let app = Gymemo.launch(
      store: "settings-\(prefix)", sample: true, tab: "settings", textSize: textSize,
      language: language)
    app.buttons["open-exercises"].required("the settings list")
    checkSettingsGrowth(app, reference: reference)
    try check(app, "08-settings")
    try checkBelow(app, "08-settings")
  }

  func run() throws {
    let reference = settingsReference()
    let bench = Self.benchPress[language] ?? ""
    let app = Gymemo.launch(
      store: "tour-\(prefix)", sample: true, textSize: textSize, language: language)
    app.staticTexts["previous-session-\(bench)"].required("the bench press section")
    XCTAssertEqual(app.tabBars.buttons.element(boundBy: 0).label, Self.logTab[language])
    try check(app, "01-log")
    try checkBelow(app, "01-log")
    if textSize != nil {
      let identifier = "weight-\(bench)"
      app.textFields[identifier].scrollAndTap(in: app)
      let original = try XCTUnwrap(app.textFields[identifier].value as? String)
      app.fill(identifier, with: "")
      try check(app, "01-log-empty-weight")
      app.fill(identifier, with: original)
    }

    app.buttons["add-exercise"].tap()
    app.buttons["create-exercise"].required("the exercise picker")
    try check(app, "02-exercise-picker")
    app.buttons["sheet-cancel"].tap()

    app.buttons["set-1-\(bench)"].scrollAndTap(in: app)
    app.textFields["edit-weight"].required("the set editor")
    try check(app, "03-set-editor")
    app.buttons["sheet-cancel"].tap()

    app.open(.history)
    app.buttons["day-2026-11-06"].required("the history list")
    try check(app, "04-history")
    app.buttons["log-another-day"].tap()
    app.datePickers.firstMatch.required("the day picker")
    try check(app, "05-day-picker")
    app.buttons["sheet-cancel"].tap()

    app.open(.analysis)
    app.staticTexts["weekly-headline"].required("the weekly headline")
    try check(app, "06-analysis")
    app.buttons["progress-\(bench)"].scrollAndTap(in: app)
    app.any("range").required("the range picker")
    try check(app, "07-exercise-progress")
    try checkBelow(app, "07-exercise-progress")

    app.open(.settings)
    app.buttons["open-exercises"].required("the settings list")
    checkSettingsGrowth(app, reference: reference)
    try check(app, "08-settings")
    try checkBelow(app, "08-settings")
    app.buttons["open-exercises"].tap()
    app.buttons["manage-\(bench)"].required("the exercise list")
    try check(app, "09-exercises")
    app.buttons["manage-\(bench)"].tap()
    app.textFields["exercise-name"].required("the exercise editor")
    try check(app, "10-exercise-editor")
    app.buttons["sheet-cancel"].tap()
    app.goBack()
    app.buttons["open-backup"].required("the settings list").tap()
    app.buttons["export-backup"].required("the backup screen")
    try check(app, "11-backup")
    try checkBelow(app, "11-backup")

    app.goBack()
    app.buttons["open-privacy"].scrollAndTap(in: app)
    try PrivacyTour.read(in: app) { page in
      try check(app, page == 0 ? "12-privacy" : "12-privacy+\(page)")
    }
    app.goBack()
    app.buttons["open-watch"].scrollAndTap(in: app)
    try check(app, "13-watch-help")
    try checkBelow(app, "13-watch-help")
  }
}

final class ScreenshotTests: XCTestCase {
  @MainActor
  func testEveryPrivacyFactPassesTheAuditAtTheLargestTextSizeInEnglish() throws {
    try ScreenTour(
      test: self, prefix: "privacy-en-largest", textSize: Gymemo.largestTextSize,
      audits: .all.subtracting(.contrast)
    ).runPrivacy()
  }

  @MainActor
  func testEveryPrivacyFactPassesTheAuditInEachLanguageAndTextSize() throws {
    try PrivacyTour.audit(test: self, prefix: "privacy-light", audits: .all.subtracting(.contrast))
  }

  @MainActor
  func testSettingsPassesTheAuditAtTheLargestTextSizeInEachLanguage() throws {
    for language in ["en", "ja", "zh-Hans", "zh-Hant"] {
      try ScreenTour(
        test: self, prefix: "settings-large-\(language)", language: language,
        textSize: Gymemo.largestTextSize, audits: .all.subtracting(.contrast)
      ).runSettings()
    }
  }

  @MainActor
  func testEveryScreenPassesTheAudit() throws {
    try ScreenTour(test: self, prefix: "light").run()
  }

  @MainActor
  func testEveryScreenPassesTheAuditAtTheLargestTextSize() throws {
    try ScreenTour(
      test: self, prefix: "large", textSize: Gymemo.largestTextSize,
      audits: .all.subtracting(.contrast)
    ).run()
  }

  @MainActor
  func testEveryScreenPassesTheAuditAtTheLargestTextSizeInJapanese() throws {
    try ScreenTour(
      test: self, prefix: "ja-large", language: "ja", textSize: Gymemo.largestTextSize,
      audits: .all.subtracting(.contrast)
    ).run()
  }

  @MainActor
  func testEveryScreenPassesTheAuditAtTheLargestTextSizeInSimplifiedChinese() throws {
    try ScreenTour(
      test: self, prefix: "zh-hans-large", language: "zh-Hans", textSize: Gymemo.largestTextSize,
      audits: .all.subtracting(.contrast)
    ).run()
  }

  @MainActor
  func testEveryScreenPassesTheAuditAtTheLargestTextSizeInTraditionalChinese() throws {
    try ScreenTour(
      test: self, prefix: "zh-hant-large", language: "zh-Hant", textSize: Gymemo.largestTextSize,
      audits: .all.subtracting(.contrast)
    ).run()
  }

  @MainActor
  func testEveryScreenPassesTheAuditInJapanese() throws {
    try ScreenTour(test: self, prefix: "ja", language: "ja").run()
  }

  @MainActor
  func testEveryScreenPassesTheAuditInSimplifiedChinese() throws {
    try ScreenTour(test: self, prefix: "zh-hans", language: "zh-Hans").run()
  }

  @MainActor
  func testEveryScreenPassesTheAuditInTraditionalChinese() throws {
    try ScreenTour(test: self, prefix: "zh-hant", language: "zh-Hant").run()
  }
}

/// The scenario that the check command runs while the simulator shows the dark appearance.
final class DarkAppearanceTests: XCTestCase {
  @MainActor
  func testEveryPrivacyFactPassesTheAuditInEachLanguageAndTextSize() throws {
    try PrivacyTour.audit(test: self, prefix: "privacy-dark", audits: .all.subtracting(.contrast))
  }

  @MainActor
  func testEveryScreenPassesTheAudit() throws {
    try ScreenTour(test: self, prefix: "dark").run()
  }
}

/// The scenario that the check command runs while the simulator increases the contrast in the light appearance.
final class IncreasedContrastTests: XCTestCase {
  @MainActor
  func testEveryPrivacyFactPassesTheAuditInEachLanguageAndTextSize() throws {
    try PrivacyTour.audit(test: self, prefix: "privacy-contrast", audits: .all)
  }

  @MainActor
  func testEveryScreenPassesTheAuditWithIncreasedContrast() throws {
    try ScreenTour(test: self, prefix: "contrast", audits: .all.subtracting(.textClipped)).run()
  }
}

/// The scenario that the check command runs while the simulator increases the contrast in the dark appearance.
final class DarkIncreasedContrastTests: XCTestCase {
  @MainActor
  func testEveryPrivacyFactPassesTheAuditInEachLanguageAndTextSize() throws {
    try PrivacyTour.audit(test: self, prefix: "privacy-dark-contrast", audits: .all)
  }

  @MainActor
  func testEveryScreenPassesTheAuditWithIncreasedContrast() throws {
    try ScreenTour(test: self, prefix: "dark-contrast", audits: .all.subtracting(.textClipped))
      .run()
  }
}
