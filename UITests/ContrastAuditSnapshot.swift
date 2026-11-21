import CoreGraphics
import XCTest

struct CapturedContrastFrames {
  struct Key: Equatable {
    let type: XCUIElement.ElementType
    let identifier: String
    let label: String
  }

  struct Element {
    let key: Key
    let frame: CGRect
  }

  let elements: [Element]

  func frame(for key: Key) -> CGRect? {
    guard !key.identifier.isEmpty, !key.label.isEmpty else { return nil }
    let matches = elements.filter { $0.key == key }
    return matches.count == 1 ? matches.first?.frame : nil
  }
}

@MainActor
struct ContrastAuditSnapshot {
  private static let managedExercise = "Seated Row"
  private static let managedExerciseIdentifier = "manage-\(managedExercise)"
  private let viewport: ContentViewport
  private let image: CGImage
  private let frames: CapturedContrastFrames

  init(_ app: XCUIApplication, screen: String) throws {
    viewport = ContentViewport(app)
    let texts = app.staticTexts.allElementsBoundByIndex
    let buttons =
      screen == "09-exercises"
      ? app.buttons.matching(identifier: Self.managedExerciseIdentifier).allElementsBoundByIndex
      : []
    frames = CapturedContrastFrames(
      elements: (texts + buttons).map { element in
        let key = CapturedContrastFrames.Key(
          type: element.elementType, identifier: element.identifier, label: element.label)
        return CapturedContrastFrames.Element(key: key, frame: element.frame)
      })
    image = try XCTUnwrap(app.screenshot().image.cgImage)
  }

  static func extent(
    for key: CapturedContrastFrames.Key, on screen: String
  ) -> PrimaryTextContrast.Extent? {
    switch (screen, key.type, key.identifier) {
    case ("01-log", .staticText, let identifier)
    where identifier.hasPrefix("set-number-") || identifier.hasPrefix("previous-session-"):
      return .glyphs
    case ("02-exercise-picker", .staticText, "section-activities"),
      ("02-exercise-picker", .staticText, "section-recent"),
      ("07-exercise-progress", .staticText, "section-sets-by-day"):
      return .row
    case (_, .staticText, let identifier)
    where ["02-exercise-picker", "09-exercises"].contains(screen)
      && identifier.hasPrefix("section-body-part-"):
      return .row
    case ("09-exercises", .button, managedExerciseIdentifier) where key.label == managedExercise:
      return .glyphs
    default:
      return nil
    }
  }

  func passes(_ issue: XCUIAccessibilityAuditIssue, on screen: String, darkInk: Bool) -> Bool {
    guard issue.auditType == .contrast, let element = issue.element else { return false }
    let key = CapturedContrastFrames.Key(
      type: element.elementType, identifier: element.identifier, label: element.label)
    guard let extent = Self.extent(for: key, on: screen), let frame = frames.frame(for: key)
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
