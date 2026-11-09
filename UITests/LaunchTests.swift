import XCTest

final class LaunchTests: XCTestCase {
  @MainActor
  func testOpensTodayInTheLogTabWithEveryTabVisible() {
    let app = Gymemo.launch(store: "launch")
    app.navigationBars["Log"].required("today's title")
    app.staticTexts["Mon, Nov 9, 2026"].required("today's date under the title")
    app.any("empty-day").required("the empty day's guidance")
    XCTAssertEqual(
      app.tabBars.buttons.allElementsBoundByIndex.map(\.label),
      ["Log", "History", "Analysis", "Settings"])
    XCTAssertTrue(app.tabBars.buttons["Log"].isSelected)
  }
}
