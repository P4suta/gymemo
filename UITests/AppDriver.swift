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

extension XCUIApplication {
  /// Puts the keyboard away through the button above it, so that it covers nothing on the screen.
  @MainActor
  func hideKeyboard() {
    let button = buttons["hide-keyboard"]
    guard button.exists else { return }
    button.tap()
    _ = keyboards.firstMatch.waitForNonExistence(timeout: 5)
  }

  @MainActor
  func open(_ tab: TabIndex) {
    hideKeyboard()
    tabBars.buttons.element(boundBy: tab.rawValue).tap()
  }

  /// Sets the text of the field called `field` inside `container`, through the field's clear button.
  @MainActor
  func fill(_ field: String, with text: String, in container: XCUIElement? = nil) {
    let scope = container ?? self
    hideKeyboard()
    let clear = scope.buttons["clear-\(field)"]
    if clear.exists { clear.tap() }
    scope.textFields[field].scrollAndTap(in: self)
    if !text.isEmpty { typeText(text) }
  }

  /// The section of one exercise on a day's screen.
  @MainActor
  func block(_ exercise: String) -> XCUIElement {
    otherElements["exercise-\(exercise)"]
  }

  /// Picks an exercise for the open day and returns its section.
  @MainActor
  func addExercise(_ name: String) -> XCUIElement {
    buttons["add-exercise"].scrollAndTap(in: self)
    buttons["pick-\(name)"].required("\(name) in the picker").scrollAndTap(in: self)
    return block(name).required("the \(name) section")
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

  /// Scrolls the screen until the element can be tapped, then taps it.
  @MainActor
  func scrollAndTap(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    app.hideKeyboard()
    required(identifier.isEmpty ? label : identifier, file: file, line: line)
    var swipes = 0
    while !isHittable, swipes < 8 {
      app.swipeUp(velocity: .slow)
      swipes += 1
    }
    tap()
  }

  /// Fills the weight and repetitions of a section and logs the set.
  @MainActor
  func logSet(weight: String, reps: String, in app: XCUIApplication) {
    app.fill("weight", with: weight, in: self)
    app.fill("reps", with: reps, in: self)
    app.hideKeyboard()
    buttons["log-set"].scrollAndTap(in: app)
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
