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

  func testMeasuresTheWorstBackgroundOutsideAntialiasedEdges() throws {
    var pixels = Array(repeating: Pixel(255, 255, 255), count: 400)
    for row in 6...12 {
      for column in 6...12 {
        pixels[row * 20 + column] = Pixel(128, 128, 128)
      }
    }
    for row in 7...11 {
      for column in 7...11 {
        pixels[row * 20 + column] = Pixel(0, 0, 0)
      }
    }
    XCTAssertEqual(
      try XCTUnwrap(PrimaryTextContrast.renderedRatio(pixels: pixels, width: 20, darkInk: true)),
      21, accuracy: 0.000_001)
    pixels[0] = Pixel(80, 80, 80)
    XCTAssertLessThan(
      try XCTUnwrap(PrimaryTextContrast.renderedRatio(pixels: pixels, width: 20, darkInk: true)),
      4.5)
    pixels[0] = Pixel(200, 150, 100)
    XCTAssertNil(PrimaryTextContrast.renderedRatio(pixels: pixels, width: 20, darkInk: true))
    XCTAssertNil(PrimaryTextContrast.renderedRatio(pixels: pixels, width: 0, darkInk: true))
    XCTAssertNil(PrimaryTextContrast.renderedRatio(pixels: pixels, width: 21, darkInk: true))
    XCTAssertNil(PrimaryTextContrast.renderedRatio(pixels: [], width: 20, darkInk: true))
  }

  func testMeasuresWhiteInkOverVaryingDarkBackgrounds() throws {
    var pixels = Array(repeating: Pixel(0, 0, 0), count: 400)
    for row in 6...12 {
      for column in 6...12 {
        pixels[row * 20 + column] = Pixel(128, 128, 128)
      }
    }
    for row in 7...11 {
      for column in 7...11 {
        pixels[row * 20 + column] = Pixel(255, 255, 255)
      }
    }
    XCTAssertEqual(
      try XCTUnwrap(PrimaryTextContrast.renderedRatio(pixels: pixels, width: 20, darkInk: false)),
      21, accuracy: 0.000_001)
    pixels[0] = Pixel(145, 145, 145)
    XCTAssertLessThan(
      try XCTUnwrap(PrimaryTextContrast.renderedRatio(pixels: pixels, width: 20, darkInk: false)),
      4.5)
    XCTAssertNil(PrimaryTextContrast.renderedRatio(pixels: pixels, width: 20, darkInk: true))
    XCTAssertNil(
      PrimaryTextContrast.renderedRatio(
        pixels: Array(repeating: Pixel(80, 80, 80), count: 400), width: 20, darkInk: false))
  }
}
