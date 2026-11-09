import Foundation
import GymemoCore
import GymemoKit

/// Every word that the app shows, in one language and with one region's number and date formats.
/// `docs/adr/localize-with-one-tested-string-catalog.md` records the design.
public struct Copy: Sendable {
  public static let languages = ["en", "ja", "zh-Hans", "zh-Hant"]

  /// The copy in the language that the system chose for the app, with the device's region formats.
  public static let current: Copy = {
    let chosen = Bundle.preferredLocalizations(
      from: languages, forPreferences: Bundle.main.preferredLocalizations
    ).first
    return chosen.flatMap { Copy(language: $0, locale: .autoupdatingCurrent) }
      ?? Copy(bundle: .module, language: "en", locale: .autoupdatingCurrent)
  }()

  public let language: String
  public let locale: Locale
  private let bundle: Bundle

  /// The copy of one supported language, or `nil` for any other language.
  public init?(language: String, locale: Locale) {
    guard Self.languages.contains(language),
      let path = Bundle.module.path(forResource: language, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else { return nil }
    self.init(bundle: bundle, language: language, locale: locale)
  }

  private init(bundle: Bundle, language: String, locale: Locale) {
    self.bundle = bundle
    self.language = language
    self.locale = locale
  }

  public subscript(key: CopyKey) -> String {
    stored(key.rawValue) ?? key.rawValue
  }

  /// The catalog's text for `key` in this language, or `nil` when the catalog lacks it.
  func stored(_ key: String) -> String? {
    let missing = "\u{1}"
    let value = bundle.localizedString(forKey: key, value: missing, table: nil)
    return value == missing ? nil : value
  }

  func format(_ key: FormatKey, _ values: any CVarArg...) -> String {
    String(format: stored(key.rawValue) ?? key.rawValue, locale: locale, arguments: values)
  }

  /// A number with at most `fractionDigits` decimals, the region's decimal separator, and no grouping.
  func decimal(_ value: Int, dividedBy divisor: Int, fractionDigits: Int) -> String {
    (Decimal(value) / Decimal(divisor)).formatted(
      .number.precision(.fractionLength(0...fractionDigits)).grouping(.never).locale(locale))
  }

  func join(_ parts: [String]) -> String {
    parts.joined(separator: self[.listSeparator])
  }
}
