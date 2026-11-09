import GymemoCore
import Testing

@Suite struct ExerciseNameTests {
  @Test func trimsSurroundingWhitespace() {
    #expect(ExerciseName.parse("  ベンチプレス\n").map(\.text) == .success("ベンチプレス"))
    #expect(ExerciseName.parse("Bench Press").map(\.text) == .success("Bench Press"))
  }

  @Test func refusesEmptyLongOrMultilineNames() {
    #expect(ExerciseName.parse("") == .failure(.empty))
    #expect(ExerciseName.parse(" \t\n") == .failure(.empty))
    #expect(ExerciseName.parse("ベンチ\nプレス") == .failure(.controlCharacter))
    #expect(ExerciseName.parse("a\u{0}b") == .failure(.controlCharacter))
    let longest = String(repeating: "あ", count: ExerciseName.maximumLength)
    #expect(ExerciseName.parse(longest).map(\.text) == .success(longest))
    #expect(ExerciseName.parse(longest + "あ") == .failure(.tooLong))
  }

  @Test func treatsCanonicallyEquivalentTextAsOneName() {
    let composed = ExerciseName.parse("ガ")
    let decomposed = ExerciseName.parse("カ\u{3099}")
    #expect(composed == decomposed)
  }

  @Test func bodyPartsKeepStableStoredNames() {
    #expect(
      BodyPart.allCases.map(\.rawValue) == [
        "chest", "back", "legs", "shoulders", "arms", "abdominals", "other",
      ])
  }
}
