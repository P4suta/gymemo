import XCTest

/// Launches the app on a store that only one test uses, with the day fixed to a Monday.
@MainActor
enum Gymemo {
  static let largestTextSize = "UICTContentSizeCategoryAccessibilityXXXL"

  private static let locales = [
    "en": "en_US", "ja": "ja_JP", "zh-Hans": "zh_Hans_CN", "zh-Hant": "zh_Hant_TW",
  ]

  static func launch(
    store: String, reset: Bool = true, sample: Bool = false, tab: String? = nil,
    textSize: String? = nil, language: String = "en"
  ) -> XCUIApplication {
    let app = XCUIApplication()
    var arguments = [
      "-gymemo-store", store, "-gymemo-today", "2026-11-09", "-AppleLanguages", "(\(language))",
      "-AppleLocale", locales[language] ?? "en_US",
    ]
    if reset { arguments.append("-gymemo-reset") }
    if sample { arguments.append("-gymemo-sample") }
    if let tab { arguments += ["-gymemo-tab", tab] }
    if let textSize { arguments += ["-UIPreferredContentSizeCategoryName", textSize] }
    app.launchArguments = arguments
    app.launch()
    return app
  }
}

/// The tabs in the order of the tab bar, so a test finds them in any language.
enum TabIndex: Int {
  case log, history, analysis, settings
}

/// The rows of one exercise on a day's screen.
/// A list has no element for a whole section, so each row carries the exercise's name in its identifier.
@MainActor
struct ExerciseRows {
  let app: XCUIApplication
  let name: String

  var weight: XCUIElement { app.textFields["weight-\(name)"] }
  var reps: XCUIElement { app.textFields["reps-\(name)"] }
  var logButton: XCUIElement { app.buttons["log-set-\(name)"] }
  var previous: XCUIElement { app.any("previous-session-\(name)") }
  var problem: XCUIElement { app.any("problem-\(name)") }

  func set(_ number: Int) -> XCUIElement { app.buttons["set-\(number)-\(name)"] }

  func stepper(_ field: String) -> XCUIElement { app.steppers["step-\(field)-\(name)"] }

  /// Fills the weight and repetitions and logs the set.
  func log(weight: String, reps: String) {
    app.fill("weight-\(name)", with: weight)
    app.fill("reps-\(name)", with: reps)
    logButton.scrollAndTap(in: app)
  }
}

extension XCUIApplication {
  /// The element with an identifier, whatever kind of element the system made of it.
  @MainActor
  func any(_ identifier: String) -> XCUIElement {
    descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// Puts the keyboard away through the button over it, so that it covers nothing on the screen.
  @MainActor
  func hideKeyboard() {
    let button = buttons["hide-keyboard"]
    guard button.exists, button.isHittable else { return }
    button.tap()
    _ = keyboards.firstMatch.waitForNonExistence(timeout: 5)
  }

  @MainActor
  func open(_ tab: TabIndex) {
    hideKeyboard()
    tabBars.buttons.element(boundBy: tab.rawValue).tap()
  }

  /// Sets the text of a number field: focuses it, clears it through its clear button, and types.
  @MainActor
  func fill(_ field: String, with text: String) {
    hideKeyboard()
    textFields[field].scrollAndTap(in: self)
    let clear = buttons["clear-\(field)"]
    if clear.waitForExistence(timeout: 1) { clear.tap() }
    if !text.isEmpty { typeText(text) }
    hideKeyboard()
  }

  /// Replaces the text of a plain text field by deleting what it holds.
  @MainActor
  func replaceText(of field: String, with text: String) {
    let element = textFields[field]
    element.required(field)
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    let current = (element.value as? String) ?? ""
    let held = current == element.placeholderValue ? "" : current
    typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: held.count) + text)
  }

  /// The rows of an exercise that the day's screen already shows.
  @MainActor
  func rows(_ exercise: String) -> ExerciseRows {
    ExerciseRows(app: self, name: exercise)
  }

  /// Picks an exercise for the open day and returns its rows.
  @MainActor
  func addExercise(_ name: String) -> ExerciseRows {
    hideKeyboard()
    buttons["add-exercise"].required("the add button").tap()
    buttons["pick-\(name)"].scrollAndTap(in: self)
    let rows = rows(name)
    rows.weight.required("the \(name) rows")
    return rows
  }

  @MainActor
  func goBack() {
    navigationBars.buttons.element(boundBy: 0).tap()
  }
}

extension XCUIElement {
  /// The element once it exists, or a recorded failure that names it.
  @MainActor
  @discardableResult
  func required(
    _ name: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line
  ) -> XCUIElement {
    XCTAssertTrue(
      waitForExistence(timeout: timeout), "\(name) did not appear", file: file, line: line)
    return self
  }

  /// Fails unless the element is gone within the timeout.
  @MainActor
  func requiredGone(
    _ name: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertTrue(
      waitForNonExistence(timeout: timeout), "\(name) stayed on the screen", file: file, line: line)
  }

  /// Scrolls the screen until the element exists and can be tapped, then taps it.
  /// A list makes its rows on demand, so a row below the screen doesn't exist until the list scrolls to it.
  @MainActor
  func scrollAndTap(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    app.hideKeyboard()
    var swipes = 0
    while !(exists && isHittable), swipes < 12 {
      app.swipeUp(velocity: .slow)
      swipes += 1
    }
    XCTAssertTrue(
      exists, "\(identifier.isEmpty ? label : identifier) did not appear", file: file, line: line)
    tap()
  }

  /// Puts the cursor after the last character of a text view that holds a short text.
  @MainActor
  func tapAtEnd() {
    coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
  }
}

extension XCTestCase {
  /// Keeps a screenshot of the whole screen under `name` in the result bundle.
  @MainActor
  func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
