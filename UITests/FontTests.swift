import CoreText
import UIKit
import XCTest

final class FontTests: XCTestCase {
  /// Rejects fallback boxes before treating screenshots or audits as localization checks.
  /// https://developer.apple.com/documentation/coretext/ctfontcreateforstringwithlanguage(_:_:_:_:)
  @MainActor
  func testSystemFontsContainTheSupportedScripts() throws {
    let roles: [CTFontUIFontType] = [.system, .emphasizedSystem]
    for (language, text) in [("en", "Log"), ("ja", "記録"), ("zh-Hans", "记录"), ("zh-Hant", "紀錄")] {
      for role in roles {
        let base = try XCTUnwrap(
          CTFontCreateUIFontForLanguage(role, UIFont.systemFontSize, language as CFString))
        let font = CTFontCreateForStringWithLanguage(
          base, text as CFString, CFRange(location: 0, length: text.utf16.count),
          language as CFString)
        let name = CTFontCopyPostScriptName(font) as String
        XCTAssertFalse(name.lowercased().contains("lastresort"), "\(language): \(name)")
        let characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        XCTAssertTrue(
          CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count),
          "\(language): \(name) couldn't map the sample characters")
        XCTAssertFalse(glyphs.contains(0), "\(language): \(name) returned missing glyphs")
      }
    }
  }
}
