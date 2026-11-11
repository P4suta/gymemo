import XCTest

final class ContentViewportTests: XCTestCase {
  private let bounds = CGRect(x: 10, y: 20, width: 1000, height: 800)
  private let navigation = CGRect(x: 10, y: 60, width: 1000, height: 60)

  func testKeepsContentBetweenNavigationAndBottomTabs() {
    let viewport = ContentViewport(
      bounds: bounds, navigationBar: navigation,
      tabBar: CGRect(x: 110, y: 740, width: 800, height: 60))
    XCTAssertEqual(viewport.frame, CGRect(x: 10, y: 120, width: 1000, height: 620))
    XCTAssertFalse(viewport.tabBarCovers(CGRect(x: 100, y: 400, width: 100, height: 30)))
    XCTAssertTrue(viewport.tabBarCovers(CGRect(x: 100, y: 730, width: 100, height: 30)))
  }

  func testKeepsContentBelowTopTabsAndRejectsUncoveredText() {
    for tabBar in [
      CGRect(x: 10, y: 20, width: 1000, height: 40),
      CGRect(x: 510, y: 60, width: 500, height: 60),
      CGRect(x: 10, y: 120, width: 1000, height: 40),
    ] {
      let viewport = ContentViewport(bounds: bounds, navigationBar: navigation, tabBar: tabBar)
      let top = max(navigation.maxY, tabBar.maxY)
      XCTAssertEqual(
        viewport.frame, CGRect(x: 10, y: top, width: 1000, height: bounds.maxY - top))
      XCTAssertFalse(viewport.tabBarCovers(CGRect(x: 100, y: 400, width: 100, height: 30)))
      XCTAssertTrue(
        viewport.tabBarCovers(CGRect(x: tabBar.minX + 10, y: tabBar.minY, width: 100, height: 30)))
    }
  }

  func testTopTabsLeaveTitlesOutsideTheirFrameUncovered() {
    let viewport = ContentViewport(
      bounds: bounds, navigationBar: navigation,
      tabBar: CGRect(x: 510, y: 60, width: 500, height: 60))
    for text in [
      CGRect(x: 100, y: 60, width: 100, height: 30),
      CGRect(x: 550, y: 20, width: 100, height: 30),
      CGRect(x: 550, y: 130, width: 100, height: 30),
      .zero,
    ] {
      XCTAssertFalse(viewport.tabBarCovers(text), "\(text)")
    }
  }

  func testBottomTabsLeaveTextOutsideTheirFrameUncovered() {
    let viewport = ContentViewport(
      bounds: bounds, navigationBar: navigation,
      tabBar: CGRect(x: 110, y: 740, width: 800, height: 60))
    for text in [
      CGRect(x: 10, y: 740, width: 50, height: 30),
      CGRect(x: 950, y: 740, width: 50, height: 30),
      CGRect(x: 200, y: 810, width: 100, height: 10),
      CGRect(x: 200, y: 700, width: 100, height: 30),
      .zero,
    ] {
      XCTAssertFalse(viewport.tabBarCovers(text), "\(text)")
    }
  }

  func testKeepsTheFullAvailableAreaWithoutTabs() {
    let viewport = ContentViewport(bounds: bounds, navigationBar: navigation, tabBar: .zero)
    XCTAssertEqual(viewport.frame, CGRect(x: 10, y: 120, width: 1000, height: 700))
    XCTAssertFalse(viewport.tabBarCovers(CGRect(x: 100, y: 400, width: 100, height: 30)))
  }
}
