import CoreGraphics
import Foundation
import XCTest

enum PrimaryTextContrast {
  struct Pixel: Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
      self.red = red
      self.green = green
      self.blue = blue
    }

    var luminance: Double {
      func linear(_ component: UInt8) -> Double {
        let value = Double(component) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
  }

  // The ratio follows https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio.
  static func ratio(pixels: [Pixel]) -> Double? {
    let counts = Dictionary(pixels.map { ($0, 1) }, uniquingKeysWith: +)
    guard let background = mostCommon(counts),
      max(background.red, background.green, background.blue)
        - min(background.red, background.green, background.blue) <= 4
    else { return nil }
    let backgroundColors = counts.filter { pixel, _ in
      abs(Int(pixel.red) - Int(background.red)) <= 4
        && abs(Int(pixel.green) - Int(background.green)) <= 4
        && abs(Int(pixel.blue) - Int(background.blue)) <= 4
    }
    guard Double(backgroundColors.values.reduce(0, +)) / Double(pixels.count) >= 0.25 else {
      return nil
    }
    let darkInk = background.luminance > 0.5
    let ink = counts.filter { pixel, _ in
      darkInk
        ? max(pixel.red, pixel.green, pixel.blue) <= 16
        : min(pixel.red, pixel.green, pixel.blue) >= 239
    }
    guard let foreground = mostCommon(ink), let count = ink[foreground],
      count >= 20, Double(count) / Double(pixels.count) >= 0.01
    else { return nil }
    let backgrounds = backgroundColors.keys.map(\.luminance)
    guard let backgroundLuminance = darkInk ? backgrounds.min() : backgrounds.max() else {
      return nil
    }
    let light = max(foreground.luminance, backgroundLuminance)
    let dark = min(foreground.luminance, backgroundLuminance)
    return (light + 0.05) / (dark + 0.05)
  }

  private static func mostCommon(_ counts: [Pixel: Int]) -> Pixel? {
    guard let maximum = counts.values.max() else { return nil }
    let candidates = counts.filter { $0.value == maximum }
    guard candidates.count == 1 else { return nil }
    return candidates.first?.key
  }

  static func renderedRatio(pixels: [Pixel], width: Int, darkInk: Bool) -> Double? {
    guard width > 0, !pixels.isEmpty, pixels.count.isMultiple(of: width) else { return nil }
    let height = pixels.count / width
    func isInk(_ pixel: Pixel) -> Bool {
      darkInk
        ? max(pixel.red, pixel.green, pixel.blue) <= 16
        : min(pixel.red, pixel.green, pixel.blue) >= 239
    }
    let ink = pixels.filter(isInk)
    guard ink.count >= 20, Double(ink.count) / Double(pixels.count) >= 0.01 else { return nil }
    var backgrounds: [Double] = []
    for (index, pixel) in pixels.enumerated() where !isInk(pixel) {
      guard max(pixel.red, pixel.green, pixel.blue) - min(pixel.red, pixel.green, pixel.blue) <= 8
      else { return nil }
      let x = index % width
      let y = index / width
      // Ignore only the antialiased edge beside primary ink.
      let besideInk = (max(0, y - 2)...min(height - 1, y + 2)).contains { row in
        (max(0, x - 2)...min(width - 1, x + 2)).contains { column in
          isInk(pixels[row * width + column])
        }
      }
      if !besideInk { backgrounds.append(pixel.luminance) }
    }
    guard Double(backgrounds.count) / Double(pixels.count) >= 0.25,
      let foreground = darkInk ? ink.map(\.luminance).max() : ink.map(\.luminance).min(),
      let background = darkInk ? backgrounds.min() : backgrounds.max(),
      darkInk ? foreground < background : foreground > background
    else { return nil }
    return (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
  }

  @MainActor
  static func measure(
    _ element: XCUIElement, in app: XCUIApplication, darkInk: Bool? = nil
  ) -> Double? {
    guard let image = app.screenshot().image.cgImage else { return nil }
    return measure(frame: element.frame, bounds: app.frame, image: image, darkInk: darkInk)
  }

  static func measure(
    frame: CGRect, bounds: CGRect, image: CGImage, darkInk: Bool? = nil
  ) -> Double? {
    guard !frame.isEmpty, bounds.contains(frame) else { return nil }
    let scaleX = Double(image.width) / bounds.width
    let scaleY = Double(image.height) / bounds.height
    let crop = CGRect(
      x: (frame.minX - bounds.minX) * scaleX, y: (frame.minY - bounds.minY) * scaleY,
      width: frame.width * scaleX, height: frame.height * scaleY
    ).integral
    guard let image = image.cropping(to: crop),
      let space = CGColorSpace(name: CGColorSpace.sRGB)
    else { return nil }
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let decoded = bytes.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard decoded else { return nil }
    var pixels: [Pixel] = []
    pixels.reserveCapacity(width * height)
    for index in stride(from: 0, to: bytes.count, by: 4) {
      guard bytes[index + 3] == 255 else { return nil }
      pixels.append(Pixel(bytes[index], bytes[index + 1], bytes[index + 2]))
    }
    if let darkInk { return renderedRatio(pixels: pixels, width: width, darkInk: darkInk) }
    return ratio(pixels: pixels)
  }
}
