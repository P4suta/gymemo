import GymemoCore
import Testing

@Suite struct MemoTests {
  @Test func keepsATextOfTheLargestLengthAndRefusesOneCharacterMore() throws {
    let longest = String(repeating: "あ", count: Memo.maximumLength)
    #expect(try Memo.parse(longest).get()?.text == longest)
    #expect(Memo.parse(longest + "あ") == .failure(.tooLong))
  }

  @Test func measuresTheLengthInCharactersAfterTrimming() throws {
    let longest = String(repeating: "カ\u{3099}", count: Memo.maximumLength)
    #expect(longest.unicodeScalars.count == 2 * Memo.maximumLength)
    #expect(try Memo.parse(" \n" + longest + "\n ").get()?.text == longest)
    #expect(Memo.parse(" \n" + longest + "カ\u{3099}\n ") == .failure(.tooLong))
  }
}
