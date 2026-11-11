import XCTest

final class PrimaryTextContrastTests: XCTestCase {
  private typealias Pixel = PrimaryTextContrast.Pixel

  private func sample(background: Pixel, ink: Pixel, inkCount: Int = 40) -> [Pixel] {
    Array(repeating: background, count: 200) + Array(repeating: ink, count: inkCount)
  }

  func testMeasuresOpaquePrimaryTextInBothAppearances() throws {
    for (background, ink) in [
      (Pixel(255, 255, 255), Pixel(0, 0, 0)),
      (Pixel(0, 0, 0), Pixel(255, 255, 255)),
    ] {
      XCTAssertEqual(
        try XCTUnwrap(PrimaryTextContrast.ratio(pixels: sample(background: background, ink: ink))),
        21, accuracy: 0.000_001)
    }
    XCTAssertEqual(
      try XCTUnwrap(
        PrimaryTextContrast.ratio(
          pixels: sample(background: Pixel(201, 201, 201), ink: Pixel(0, 0, 0)))),
      12.681_568_357_823_28, accuracy: 0.000_001)
  }

  func testKeepsInsufficientContrastBelowTheRequiredRatio() throws {
    let ratio = try XCTUnwrap(
      PrimaryTextContrast.ratio(
        pixels: sample(background: Pixel(145, 145, 145), ink: Pixel(255, 255, 255))))
    XCTAssertLessThan(ratio, 4.5)
    XCTAssertGreaterThan(ratio, 3)
  }

  func testUsesTheLeastContrastingNearbyBackgroundColor() throws {
    let pixels =
      sample(background: Pixel(205, 205, 205), ink: Pixel(0, 0, 0))
      + Array(repeating: Pixel(201, 201, 201), count: 100)
    XCTAssertEqual(
      try XCTUnwrap(PrimaryTextContrast.ratio(pixels: pixels)),
      12.681_568_357_823_28, accuracy: 0.000_001)
  }

  func testRefusesMissingInkAndIsolatedDarkPixels() {
    XCTAssertNil(PrimaryTextContrast.ratio(pixels: []))
    XCTAssertNil(
      PrimaryTextContrast.ratio(pixels: Array(repeating: Pixel(205, 205, 205), count: 200)))
    XCTAssertNil(
      PrimaryTextContrast.ratio(
        pixels: sample(background: Pixel(205, 205, 205), ink: Pixel(0, 0, 0), inkCount: 1)))
    XCTAssertNil(
      PrimaryTextContrast.ratio(
        pixels: sample(background: Pixel(205, 205, 205), ink: Pixel(150, 150, 150))))
  }

  func testRefusesAnAmbiguousBackground() {
    let pixels =
      Array(repeating: Pixel(205, 205, 205), count: 100)
      + Array(repeating: Pixel(210, 210, 210), count: 100)
      + Array(repeating: Pixel(0, 0, 0), count: 40)
    XCTAssertNil(PrimaryTextContrast.ratio(pixels: pixels))
    XCTAssertNil(
      PrimaryTextContrast.ratio(
        pixels: sample(background: Pixel(200, 150, 100), ink: Pixel(0, 0, 0))))
  }
}
