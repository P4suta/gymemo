import XCTest

struct ContentViewport {
  let bounds: CGRect
  let navigationBar: CGRect
  let tabBar: CGRect

  private var tabsAtBottom: Bool { tabBar.midY > bounds.midY }

  var frame: CGRect {
    let top = max(
      bounds.minY, navigationBar.maxY,
      tabBar.isEmpty || tabsAtBottom ? bounds.minY : tabBar.maxY)
    let bottom = tabBar.isEmpty || !tabsAtBottom ? bounds.maxY : min(bounds.maxY, tabBar.minY)
    return CGRect(x: bounds.minX, y: top, width: bounds.width, height: max(0, bottom - top))
  }

  func contains(_ text: CGRect, pointSizeOfPixel pixel: CGSize) -> Bool {
    let viewport = frame
    let coordinates = [
      text.minX, text.minY, text.maxX, text.maxY,
      viewport.minX, viewport.minY, viewport.maxX, viewport.maxY,
    ]
    guard !text.isEmpty, !viewport.isEmpty, coordinates.allSatisfy(\.isFinite),
      pixel.width > 0, pixel.width <= 1, pixel.height > 0, pixel.height <= 1
    else { return false }
    return text.minX >= (viewport.minX - pixel.width).nextDown
      && text.minY >= (viewport.minY - pixel.height).nextDown
      && text.maxX <= (viewport.maxX + pixel.width).nextUp
      && text.maxY <= (viewport.maxY + pixel.height).nextUp
  }

  func tabBarCovers(_ text: CGRect) -> Bool {
    !tabBar.isEmpty && tabBar.intersects(text)
  }
}

extension ContentViewport {
  @MainActor
  init(_ app: XCUIApplication) {
    let navigation = app.navigationBars.firstMatch
    let tabs = app.tabBars.firstMatch
    self.init(
      bounds: app.frame, navigationBar: navigation.exists ? navigation.frame : .zero,
      tabBar: tabs.exists ? tabs.frame : .zero)
  }
}
