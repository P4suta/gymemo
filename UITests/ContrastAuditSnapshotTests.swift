import XCTest

final class ContrastAuditSnapshotTests: XCTestCase {
  func testBindsOnlyOneCapturedIdentifierAndItsUnchangedLabel() {
    let first = CGRect(x: 40, y: 320, width: 10, height: 20)
    let second = CGRect(x: 40, y: 807, width: 10, height: 20)
    let frames = CapturedContrastFrames(texts: [
      .init(identifier: "set-number-bench", label: "1", frame: first),
      .init(identifier: "set-number-pull-up", label: "1", frame: second),
    ])
    XCTAssertEqual(frames.frame(identifier: "set-number-pull-up", label: "1"), second)
    XCTAssertNil(frames.frame(identifier: "set-number-pull-up", label: "2"))
    XCTAssertNil(frames.frame(identifier: "set-number-deleted", label: "1"))
    XCTAssertNil(frames.frame(identifier: "", label: "1"))
    XCTAssertNil(frames.frame(identifier: "set-number-bench", label: ""))
    let duplicates = CapturedContrastFrames(texts: frames.texts + [frames.texts[1]])
    XCTAssertNil(duplicates.frame(identifier: "set-number-pull-up", label: "1"))
  }

  @MainActor
  func testRestrictsMeasuredReportsToTheirCapturedScreenAndTextRole() {
    XCTAssertNotNil(ContrastAuditSnapshot.extent(identifier: "set-number-a", screen: "01-log"))
    XCTAssertNotNil(
      ContrastAuditSnapshot.extent(identifier: "section-recent", screen: "02-exercise-picker"))
    for screen in ["02-exercise-picker", "09-exercises"] {
      XCTAssertNotNil(
        ContrastAuditSnapshot.extent(identifier: "section-body-part-chest", screen: screen))
    }
    XCTAssertNil(ContrastAuditSnapshot.extent(identifier: "section-recent", screen: "01-log"))
    XCTAssertNil(ContrastAuditSnapshot.extent(identifier: "set-number-a", screen: "09-exercises"))
    XCTAssertNil(ContrastAuditSnapshot.extent(identifier: "unknown", screen: "02-exercise-picker"))
    XCTAssertNil(ContrastAuditSnapshot.extent(identifier: "section-recent", screen: "12-privacy"))
  }
}
