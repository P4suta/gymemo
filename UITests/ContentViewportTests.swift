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

  func testAcceptsOnePixelOfRoundingAtTheSettingsFooter() {
    let viewport = ContentViewport(
      bounds: CGRect(x: 0, y: 0, width: 420, height: 912),
      navigationBar: CGRect(x: 0, y: 0, width: 420, height: 122),
      tabBar: CGRect(x: 0, y: 829, width: 420, height: 83))
    let footer = CGRect(
      x: 20, y: 762.6666666666665, width: 380, height: 66.66666666666663)
    XCTAssertTrue(
      viewport.contains(footer, pointSizeOfPixel: CGSize(width: 1.0 / 3, height: 1.0 / 3)))
  }

  func testRoundingAllowsOnePixelAndRejectsTwoPixelsAtEveryEdge() {
    let viewport = ContentViewport(
      bounds: bounds, navigationBar: navigation,
      tabBar: CGRect(x: 110, y: 740, width: 800, height: 60))
    for scale in [CGFloat(1), 2, 3] {
      let pixel = CGSize(width: 1 / scale, height: 1 / scale)
      for (overflow, visible) in [(1 / scale, true), (2 / scale, false)] {
        for text in [
          CGRect(x: 10 - overflow, y: 400, width: 100, height: 30),
          CGRect(x: 910 + overflow, y: 400, width: 100, height: 30),
          CGRect(x: 100, y: 120 - overflow, width: 100, height: 30),
          CGRect(x: 100, y: 710 + overflow, width: 100, height: 30),
        ] {
          XCTAssertEqual(
            viewport.contains(text, pointSizeOfPixel: pixel), visible, "\(scale): \(text)")
        }
      }
    }
  }

  func testRoundingRejectsEmptyOrInvalidMeasurements() {
    let viewport = ContentViewport(bounds: bounds, navigationBar: navigation, tabBar: .zero)
    let text = CGRect(x: 100, y: 400, width: 100, height: 30)
    for pixel in [
      CGSize.zero, CGSize(width: -1, height: 1), CGSize(width: 1, height: -1),
      CGSize(width: 2, height: 1), CGSize(width: 1, height: 2),
      CGSize(width: CGFloat.nan, height: 1), CGSize(width: 1, height: CGFloat.infinity),
    ] {
      XCTAssertFalse(viewport.contains(text, pointSizeOfPixel: pixel))
    }
    let pixel = CGSize(width: 0.5, height: 0.5)
    for text in [
      CGRect.zero, .null, .infinite, CGRect(x: CGFloat.nan, y: 400, width: 100, height: 30),
    ] {
      XCTAssertFalse(viewport.contains(text, pointSizeOfPixel: pixel))
    }
    let empty = ContentViewport(bounds: .zero, navigationBar: .zero, tabBar: .zero)
    XCTAssertFalse(empty.contains(text, pointSizeOfPixel: pixel))
  }
}
