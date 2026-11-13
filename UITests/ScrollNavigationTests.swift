import XCTest

final class ScrollNavigationTests: XCTestCase {
  @MainActor
  func testReturnsFromTheLastRowToTheFirstSetAtTheLargestJapaneseTextSize() {
    let app = Gymemo.launch(
      store: "scroll-first-set-ja", sample: true, textSize: Gymemo.largestTextSize, language: "ja")
    let first = app.rows("ベンチプレス").set(1)
    app.buttons["edit-note"].scrollAndTap(in: app)
    app.textViews["note-editor"].required("the note editor at the end of the log")
    app.buttons["sheet-cancel"].tap()
    app.textViews["note-editor"].requiredGone("the note editor")

    first.scrollAndTap(in: app)
    app.textFields["edit-weight"].required("the first set editor")
    XCTAssertEqual(app.staticTexts["edit-exercise"].label, "ベンチプレス")
    app.buttons["sheet-cancel"].tap()
    app.textFields["edit-weight"].requiredGone("the set editor")

    app.buttons["edit-note"].scrollAndTap(in: app)
    app.textViews["note-editor"].required("the note editor after scrolling down again")
  }
}
