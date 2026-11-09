import XCTest

/// Launches the app on a store that only one test uses, with the day fixed to a Monday.
@MainActor
enum Gymemo {
  static func launch(
    store: String, reset: Bool = true, sample: Bool = false, tab: String? = nil,
    textSize: String? = nil
  ) -> XCUIApplication {
    let app = XCUIApplication()
    var arguments = [
      "-gymemo-store", store, "-gymemo-today", "2026-11-09", "-AppleLanguages", "(ja)",
      "-AppleLocale", "ja_JP",
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

  /// Scrolls the nearest scroll view until the element can be tapped, then taps it.
  @MainActor
  func scrollAndTap(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    required(identifier.isEmpty ? label : identifier, file: file, line: line)
    var swipes = 0
    while !isHittable, swipes < 8 {
      app.swipeUp(velocity: .slow)
      swipes += 1
    }
    tap()
  }

  /// Replaces the text of a field.
  @MainActor
  func replaceText(with text: String) {
    tap()
    let current = (value as? String) ?? ""
    typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
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
