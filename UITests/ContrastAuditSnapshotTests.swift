import XCTest

final class ContrastAuditSnapshotTests: XCTestCase {
  func testBindsOneCapturedElementWithItsTypeIdentifierAndLabel() {
    let first = CGRect(x: 40, y: 320, width: 10, height: 20)
    let second = CGRect(x: 40, y: 807, width: 10, height: 20)
    let bench = CapturedContrastFrames.Key(
      type: .staticText, identifier: "set-number-bench", label: "1")
    let pullUp = CapturedContrastFrames.Key(
      type: .staticText, identifier: "set-number-pull-up", label: "1")
    let frames = CapturedContrastFrames(elements: [
      .init(key: bench, frame: first),
      .init(key: pullUp, frame: second),
    ])
    XCTAssertEqual(frames.frame(for: pullUp), second)
    XCTAssertNil(
      frames.frame(for: .init(type: .button, identifier: pullUp.identifier, label: pullUp.label)))
    XCTAssertNil(
      frames.frame(for: .init(type: .staticText, identifier: pullUp.identifier, label: "2")))
    XCTAssertNil(
      frames.frame(for: .init(type: .staticText, identifier: "set-number-deleted", label: "1")))
    XCTAssertNil(frames.frame(for: .init(type: .staticText, identifier: "", label: "1")))
    XCTAssertNil(
      frames.frame(for: .init(type: .staticText, identifier: pullUp.identifier, label: "")))
    let duplicates = CapturedContrastFrames(elements: frames.elements + [frames.elements[1]])
    XCTAssertNil(duplicates.frame(for: pullUp))
  }

  @MainActor
  func testRestrictsMeasuredReportsToTheirCapturedScreenAndTextRole() {
    func textExtent(_ identifier: String, on screen: String) -> PrimaryTextContrast.Extent? {
      ContrastAuditSnapshot.extent(
        for: .init(type: .staticText, identifier: identifier, label: "Sample"), on: screen)
    }
    XCTAssertNotNil(textExtent("set-number-a", on: "01-log"))
    XCTAssertNotNil(textExtent("previous-session-Pull-Up", on: "01-log"))
    XCTAssertNotNil(textExtent("section-activities", on: "02-exercise-picker"))
    XCTAssertNotNil(textExtent("section-recent", on: "02-exercise-picker"))
    XCTAssertNotNil(textExtent("section-sets-by-day", on: "07-exercise-progress"))
    for screen in ["02-exercise-picker", "09-exercises"] {
      XCTAssertNotNil(textExtent("section-body-part-chest", on: screen))
    }
    XCTAssertNil(textExtent("section-recent", on: "01-log"))
    XCTAssertNil(textExtent("section-activities", on: "09-exercises"))
    XCTAssertNil(textExtent("set-number-a", on: "09-exercises"))
    XCTAssertNil(textExtent("previous-session-Pull-Up", on: "09-exercises"))
    XCTAssertNil(textExtent("unknown", on: "02-exercise-picker"))
    XCTAssertNil(textExtent("section-recent", on: "12-privacy"))
    XCTAssertNil(textExtent("section-sets-by-day", on: "06-analysis"))
    XCTAssertNil(textExtent("section-recent", on: "07-exercise-progress"))
    XCTAssertNil(textExtent("manage-Seated Row", on: "09-exercises"))

    let row = CapturedContrastFrames.Key(
      type: .button, identifier: "manage-Seated Row", label: "Seated Row")
    XCTAssertNotNil(ContrastAuditSnapshot.extent(for: row, on: "09-exercises"))
    XCTAssertNil(ContrastAuditSnapshot.extent(for: row, on: "02-exercise-picker"))
    XCTAssertNil(
      ContrastAuditSnapshot.extent(
        for: .init(type: .button, identifier: row.identifier, label: "Seated Row, Hidden"),
        on: "09-exercises"))
    XCTAssertNil(
      ContrastAuditSnapshot.extent(
        for: .init(type: .button, identifier: "manage-Bench Press", label: "Bench Press"),
        on: "09-exercises"))
  }
}
