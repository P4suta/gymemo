import UIKit

@MainActor
enum PlaceholderTextFit {
  static func requiredSize(_ text: String) -> CGSize {
    let traits = UITraitCollection(
      preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
    let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
    let size = (text as NSString).size(withAttributes: [.font: font])
    return CGSize(width: ceil(size.width), height: ceil(size.height))
  }

  static func fits(_ text: String, in bounds: CGSize) -> Bool {
    guard !text.isEmpty, bounds.width.isFinite, bounds.height.isFinite else { return false }
    let required = requiredSize(text)
    return required.width <= bounds.width && required.height <= bounds.height
  }
}
