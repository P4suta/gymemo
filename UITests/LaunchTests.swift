import XCTest

final class LaunchTests: XCTestCase {
  @MainActor
  func testTheAppOpensOnTheLogHeading() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.staticTexts["記録"].waitForExistence(timeout: 10))
  }
}
