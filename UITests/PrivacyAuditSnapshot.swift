import CoreGraphics
import XCTest

@MainActor
struct PrivacyAuditSnapshot {
  private struct Key: Hashable {
    let identifier: String
    let label: String
  }

  let bounds: CGRect
  let image: CGImage
  let navigationFrame: CGRect
  let navigationTitle: String
  let tabFrame: CGRect
  private let frames: [Key: [CGRect]]

  var viewport: ContentViewport {
    ContentViewport(bounds: bounds, navigationBar: navigationFrame, tabBar: tabFrame)
  }

  init(_ app: XCUIApplication) throws {
    let viewport = ContentViewport(app)
    bounds = viewport.bounds
    navigationFrame = viewport.navigationBar
    navigationTitle = app.navigationBars.firstMatch.identifier
    tabFrame = viewport.tabBar
    var captured: [Key: [CGRect]] = [:]
    for text in app.staticTexts.allElementsBoundByIndex {
      captured[Key(identifier: text.identifier, label: text.label), default: []].append(text.frame)
    }
    frames = captured
    image = try XCTUnwrap(app.screenshot().image.cgImage)
  }

  func frame(for element: XCUIElement) -> CGRect? {
    let matches = frames[Key(identifier: element.identifier, label: element.label)] ?? []
    return matches.count == 1 ? matches.first : nil
  }

  func contrast(of element: XCUIElement, darkInk: Bool?) -> Double? {
    guard let frame = frame(for: element) else { return nil }
    return PrimaryTextContrast.measure(frame: frame, bounds: bounds, image: image, darkInk: darkInk)
  }
}
