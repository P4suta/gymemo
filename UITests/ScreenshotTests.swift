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
  /// The tours at the default contrast leave contrast to the tours that run with Increase Contrast, because the system draws secondary text under the contrast minimum by default.
  /// The accessibility guidance asks an app in that position to reach the minimum when Increase Contrast is on.
  /// See https://developer.apple.com/design/human-interface-guidelines/accessibility.
  /// Only the tours at the largest text size audit clipped text, because the audit of a smaller size predicts what those tours observe.
  var audits: XCUIAccessibilityAuditType = .all.subtracting([.contrast, .textClipped])

  /// The first starter exercise in each language, which also shows that its name is localized.
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

  /// Whether the audit reports something that the app can't change.
  private func isSystemDrawn(
    _ issue: XCUIAccessibilityAuditIssue, on screen: String, in app: XCUIApplication
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
    // A bar floats over the content, and the audit measures the text under the bar through its material.
    if element.frame.maxY > app.tabBars.firstMatch.frame.minY { return true }
    // The header of the set editor lies on the sheet's material under the sheet's bar.
    // A screenshot with Increase Contrast shows 5.5:1 between its text and its background.
    return element.identifier == "edit-exercise"
  }

  private func check(_ app: XCUIApplication, _ name: String) throws {
    test.capture("\(prefix)-\(name)")
    try app.performAccessibilityAudit(for: audits) { issue in
      if isSystemDrawn(issue, on: name, in: app) { return true }
      let element = issue.element.map { element in
        "type \(element.elementType.rawValue) identifier '\(element.identifier)' label '\(element.label)' rows \(Int(element.frame.minY))-\(Int(element.frame.maxY))"
      }
      XCTFail(
        "\(name): \(issue.compactDescription) on \(element ?? "no element"): \(issue.detailedDescription)"
      )
      return true
    }
  }

  /// Checks the part of a screen that the largest text size pushes under the first screenful, then returns to the top.
  private func checkBelow(_ app: XCUIApplication, _ name: String) throws {
    guard textSize != nil else { return }
    app.swipeUp()
    try check(app, "\(name)+below")
    app.swipeDown(velocity: .fast)
    app.swipeDown(velocity: .fast)
  }

  func run() throws {
    let bench = Self.benchPress[language] ?? ""
    let app = Gymemo.launch(
      store: "tour-\(prefix)", sample: true, textSize: textSize, language: language)
    app.staticTexts["previous-session-\(bench)"].required("the bench press section")
    XCTAssertEqual(app.tabBars.buttons.element(boundBy: 0).label, Self.logTab[language])
    try check(app, "01-log")
    try checkBelow(app, "01-log")

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
  }
}

final class ScreenshotTests: XCTestCase {
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
  func testEveryScreenPassesTheAudit() throws {
    try ScreenTour(test: self, prefix: "dark").run()
  }
}

/// The scenario that the check command runs while the simulator increases the contrast in the light appearance.
final class IncreasedContrastTests: XCTestCase {
  @MainActor
  func testEveryScreenPassesTheAuditWithIncreasedContrast() throws {
    try ScreenTour(test: self, prefix: "contrast", audits: .all.subtracting(.textClipped)).run()
  }
}

/// The scenario that the check command runs while the simulator increases the contrast in the dark appearance.
final class DarkIncreasedContrastTests: XCTestCase {
  @MainActor
  func testEveryScreenPassesTheAuditWithIncreasedContrast() throws {
    try ScreenTour(test: self, prefix: "dark-contrast", audits: .all.subtracting(.textClipped))
      .run()
  }
}
