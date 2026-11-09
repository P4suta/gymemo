import XCTest

final class LaunchTests: XCTestCase {
  @MainActor
  func testOpensTodayInTheLogTabWithEveryTabVisible() {
    let app = Gymemo.launch(store: "launch")
    app.navigationBars["2026年11月9日(月)"].required("today's title")
    app.staticTexts["empty-day"].required("the empty day's guidance")
    for tab in ["記録", "履歴", "分析", "設定"] {
      XCTAssertTrue(app.tabBars.buttons[tab].exists, "The \(tab) tab is missing")
    }
    XCTAssertTrue(app.tabBars.buttons["記録"].isSelected)
  }
}
