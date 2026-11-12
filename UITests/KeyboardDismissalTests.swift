import XCTest

final class KeyboardDismissalTests: XCTestCase {
  @MainActor
  func testDismissesNumberKeyboardsAtTheLargestTextSizeInEachLanguage() throws {
    for (language, exercise) in [
      ("en", "Bench Press"), ("ja", "ベンチプレス"),
      ("zh-Hans", "卧推"), ("zh-Hant", "臥推"),
    ] {
      let app = Gymemo.launch(
        store: "keyboard-dismissal-\(language)", sample: true,
        textSize: Gymemo.largestTextSize, language: language)
      let keyboard = app.keyboards.firstMatch
      for kind in ["weight", "reps"] {
        let field = app.textFields["\(kind)-\(exercise)"]
        field.scrollAndTap(in: app)
        let original = try XCTUnwrap(field.value as? String)
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        app.hideKeyboard()
        XCTAssertFalse(keyboard.exists)

        app.fill(field.identifier, with: "")
        XCTAssertEqual(field.value as? String, field.placeholderValue)
        XCTAssertFalse(keyboard.exists)
        app.fill(field.identifier, with: original)
        XCTAssertEqual(field.value as? String, original)
        XCTAssertFalse(keyboard.exists)

        app.hideKeyboard()
        XCTAssertFalse(keyboard.exists)
      }
    }
  }
}
