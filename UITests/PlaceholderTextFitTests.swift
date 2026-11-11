import XCTest

final class PlaceholderTextFitTests: XCTestCase {
  @MainActor
  func testTheLargestBodyPlaceholderFitsTheObservedFullWidthField() {
    XCTAssertTrue(PlaceholderTextFit.fits("Bodyweight", in: CGSize(width: 340, height: 64)))
    XCTAssertFalse(PlaceholderTextFit.fits("Bodyweight", in: CGSize(width: 215, height: 65)))
    let required = PlaceholderTextFit.requiredSize("Bodyweight")
    XCTAssertTrue(PlaceholderTextFit.fits("Bodyweight", in: required))
    XCTAssertFalse(
      PlaceholderTextFit.fits(
        "Bodyweight", in: CGSize(width: required.width - 1, height: required.height)))
    XCTAssertFalse(
      PlaceholderTextFit.fits(
        "Bodyweight", in: CGSize(width: required.width, height: required.height - 1)))
    for bounds in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 64)] {
      XCTAssertFalse(PlaceholderTextFit.fits("Bodyweight", in: bounds))
    }
    XCTAssertFalse(PlaceholderTextFit.fits("", in: required))
  }
}
