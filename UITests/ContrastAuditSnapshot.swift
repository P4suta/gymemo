import CoreGraphics
import XCTest

struct CapturedContrastFrames {
  struct Text {
    let identifier: String
    let label: String
    let frame: CGRect
  }

  let texts: [Text]

  func frame(identifier: String, label: String) -> CGRect? {
    guard !identifier.isEmpty, !label.isEmpty else { return nil }
    let matches = texts.filter { $0.identifier == identifier && $0.label == label }
    return matches.count == 1 ? matches.first?.frame : nil
  }
}

@MainActor
struct ContrastAuditSnapshot {
  private let viewport: ContentViewport
  private let image: CGImage
  private let frames: CapturedContrastFrames

  init(_ app: XCUIApplication) throws {
    viewport = ContentViewport(app)
    frames = CapturedContrastFrames(
      texts: app.staticTexts.allElementsBoundByIndex.map {
        CapturedContrastFrames.Text(identifier: $0.identifier, label: $0.label, frame: $0.frame)
      })
    image = try XCTUnwrap(app.screenshot().image.cgImage)
  }

  static func extent(identifier: String, screen: String) -> PrimaryTextContrast.Extent? {
    if screen == "01-log", identifier.hasPrefix("set-number-") { return .glyphs }
    if screen == "02-exercise-picker", identifier == "section-recent" { return .row }
    if ["02-exercise-picker", "09-exercises"].contains(screen),
      identifier.hasPrefix("section-body-part-")
    {
      return .row
    }
    return nil
  }

  func passes(_ issue: XCUIAccessibilityAuditIssue, on screen: String, darkInk: Bool) -> Bool {
    guard issue.auditType == .contrast, let element = issue.element,
      element.elementType == .staticText,
      let extent = Self.extent(identifier: element.identifier, screen: screen),
      let frame = frames.frame(identifier: element.identifier, label: element.label)
    else { return false }
    let pixel = CGSize(
      width: viewport.bounds.width / CGFloat(image.width),
      height: viewport.bounds.height / CGFloat(image.height))
    guard viewport.contains(frame, pointSizeOfPixel: pixel),
      let ratio = PrimaryTextContrast.measure(
        frame: frame, bounds: viewport.bounds, image: image, darkInk: darkInk, extent: extent),
      ratio >= 4.5
    else { return false }
    XCTContext.runActivity(named: "Captured \(element.identifier) contrast: \(ratio):1") { _ in }
    return true
  }
}
