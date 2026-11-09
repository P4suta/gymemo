import XCTest

/// Walks the sample log through every screen, audits each one, and keeps a screenshot of it.
@MainActor
struct ScreenTour {
  let test: XCTestCase
  let prefix: String
  var language = "en"
  var textSize: String?

  /// The first starter exercise in each language, which also shows that its name is localized.
  private static let benchPress = [
    "en": "Bench Press", "ja": "ベンチプレス", "zh-Hans": "卧推", "zh-Hant": "臥推",
  ]

  /// The Log tab's label in each language.
  private static let logTab = ["en": "Log", "ja": "記録", "zh-Hans": "记录", "zh-Hant": "紀錄"]

  /// Whether an issue comes from a part of the screen that the system draws and the app can't change.
  /// The graphical date picker draws its day numbers at one size and exposes its header only through its buttons.
  /// A chart draws its axis labels as plain text, and each mark carries the same value as its spoken label.
  private func isSystemDrawn(_ issue: XCUIAccessibilityAuditIssue, on screen: String) -> Bool {
    switch screen {
    case "05-day-picker": issue.auditType == .dynamicType || issue.auditType == .elementDetection
    case "06-analysis", "07-exercise-progress":
      issue.auditType == .elementDetection && issue.element == nil
    default: false
    }
  }

  /// Whether a contrast issue names scrolled text that lies outside its scroll view or that an edge cuts through.
  /// The audit measures the pixels at the text's frame, so text that has scrolled out of view fails it at any colors.
  /// The palette check in `just check` is what holds the screens to black and white.
  private func isScrolledOutOfView(
    _ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication
  ) -> Bool {
    guard issue.auditType == .contrast, let element = issue.element else { return false }
    let tabs = app.tabBars.buttons.allElementsBoundByIndex.map(\.label)
    let viewports = app.scrollViews.allElementsBoundByIndex.map(\.frame)
    return !tabs.contains(element.label) && !viewports.contains { $0.contains(element.frame) }
  }

  private func check(_ app: XCUIApplication, _ name: String) throws {
    test.capture("\(prefix)-\(name)")
    try app.performAccessibilityAudit { issue in
      if isSystemDrawn(issue, on: name) || isScrolledOutOfView(issue, in: app) { return true }
      let element = issue.element.map { element in
        "type \(element.elementType.rawValue) identifier '\(element.identifier)' label '\(element.label)'"
      }
      let frame = issue.element.map { "\($0.frame)" } ?? "none"
      let viewports = app.scrollViews.allElementsBoundByIndex.map { "\($0.frame)" }
      XCTFail(
        "\(name): \(issue.compactDescription) on \(element ?? "no element") frame \(frame) in \(viewports): \(issue.detailedDescription)"
      )
      return true
    }
  }

  func run() throws {
    let bench = Self.benchPress[language] ?? ""
    let app = Gymemo.launch(
      store: "tour-\(prefix)", sample: true, textSize: textSize, language: language)
    app.block(bench).required("the bench press section")
    XCTAssertEqual(app.tabBars.buttons.element(boundBy: 0).label, Self.logTab[language])
    try check(app, "01-log")

    app.buttons["add-exercise"].scrollAndTap(in: app)
    app.buttons["create-exercise"].required("the exercise picker")
    try check(app, "02-exercise-picker")
    app.buttons["sheet-cancel"].tap()

    app.block(bench).buttons["set-1"].scrollAndTap(in: app)
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
    app.staticTexts["best-score"].required("the best score")
    try check(app, "07-exercise-progress")

    app.open(.settings)
    app.buttons["open-exercises"].required("the settings list")
    try check(app, "08-settings")
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
  }
}

final class ScreenshotTests: XCTestCase {
  @MainActor
  func testEveryScreenPassesTheAudit() throws {
    try ScreenTour(test: self, prefix: "light").run()
  }

  @MainActor
  func testEveryScreenPassesTheAuditAtTheLargestTextSize() throws {
    try ScreenTour(test: self, prefix: "large", textSize: Gymemo.largestTextSize).run()
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

/// The scenarios that the check command runs while the simulator shows the dark appearance.
final class DarkAppearanceTests: XCTestCase {
  @MainActor
  func testEveryScreenPassesTheAudit() throws {
    try ScreenTour(test: self, prefix: "dark").run()
  }
}
