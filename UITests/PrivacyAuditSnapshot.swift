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

  func assertContrast(for facts: Set<String>, darkInk: Bool) {
    let visible = frames.flatMap { key, values in
      values.filter { frame in
        !key.label.isEmpty
          && (viewport.frame.contains(frame)
            || (key.label == navigationTitle && navigationFrame.contains(frame)))
      }.map { (key, $0) }
    }
    let identifiers = Set(visible.map { $0.0.identifier })
    XCTAssertFalse(facts.isEmpty, "Privacy contrast needs the facts reached on the current page")
    XCTAssertTrue(
      facts.isSubset(of: identifiers),
      "Privacy contrast missed reached facts: \(facts.subtracting(identifiers).sorted())")
    for (key, frame) in visible {
      let isTitle = key.label == navigationTitle && navigationFrame.contains(frame)
      guard
        let ratio = PrimaryTextContrast.measure(
          frame: frame, bounds: bounds, image: image, darkInk: isTitle ? darkInk : nil)
      else {
        XCTFail("Privacy contrast could not be measured for '\(key.identifier)': \(key.label)")
        continue
      }
      XCTContext.runActivity(named: "Measured \(key.identifier) contrast: \(ratio):1") { _ in }
      XCTAssertGreaterThanOrEqual(ratio, 4.5, "Insufficient privacy contrast: \(key.identifier)")
    }
  }
}
