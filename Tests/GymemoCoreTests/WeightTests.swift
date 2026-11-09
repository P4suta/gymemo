import GymemoCore
import Testing

@Suite struct WeightTests {
  @Test func acceptsOnlyTheSupportedRange() {
    #expect(Weight(hundredths: 0)?.hundredths == 0)
    #expect(Weight(hundredths: 99_999)?.hundredths == 99_999)
    #expect(Weight(hundredths: -1) == nil)
    #expect(Weight(hundredths: 100_000) == nil)
  }

  @Test(arguments: [
    ("60", 6000), ("62.5", 6250), ("1.25", 125), ("0", 0), (".5", 50), ("60.", 6000),
    ("062,5", 6250), (" 100 ", 10_000), ("999.99", 99_999), ("0.00", 0),
  ])
  func parsesDecimalText(text: String, hundredths: Int) {
    #expect(Weight.parse(text) == .success(Weight(hundredths: hundredths) ?? .bodyweight))
    #expect(Weight(hundredths: hundredths) != nil)
  }

  @Test(arguments: [
    ("", WeightRefusal.empty), ("   ", .empty), ("abc", .notANumber), ("-5", .notANumber),
    ("1.2.3", .notANumber), ("６０", .notANumber), (".", .notANumber), ("1e3", .notANumber),
    ("1 0", .notANumber), ("1.234", .tooPrecise), ("1000", .outOfRange),
    ("99999999999999999999999", .outOfRange),
  ])
  func refusesOtherText(text: String, refusal: WeightRefusal) {
    #expect(Weight.parse(text) == .failure(refusal))
  }

  @Test(arguments: [
    (6000, "60"), (6250, "62.5"), (125, "1.25"), (0, "0"), (50, "0.5"), (6205, "62.05"),
    (99_999, "999.99"),
  ])
  func writesTheShortestDecimalText(hundredths: Int, text: String) {
    #expect(Weight(hundredths: hundredths)?.text == text)
  }

  @Test func everyWeightSurvivesItsOwnText() {
    for hundredths in 0...Weight.maximumHundredths {
      let weight = Weight(hundredths: hundredths)
      #expect(weight != nil)
      if let weight, Weight.parse(weight.text) != .success(weight) {
        Issue.record("\(hundredths) did not survive \(weight.text)")
        return
      }
    }
  }

  @Test func ordersByMass() {
    let lighter = Weight(hundredths: 5999)
    let heavier = Weight(hundredths: 6000)
    #expect(lighter != nil && heavier != nil)
    if let lighter, let heavier { #expect(lighter < heavier) }
    #expect(Weight.bodyweight.isBodyweight)
    #expect(Weight(hundredths: 1)?.isBodyweight == false)
  }
}

@Suite struct RepsTests {
  @Test func acceptsOnlyTheSupportedRange() {
    #expect(Reps(1)?.count == 1)
    #expect(Reps(999)?.count == 999)
    #expect(Reps(0) == nil)
    #expect(Reps(1000) == nil)
    #expect(Reps(-3) == nil)
  }

  @Test(arguments: [("1", 1), ("10", 10), (" 8 ", 8), ("010", 10), ("999", 999)])
  func parsesWholeNumbers(text: String, count: Int) {
    #expect(Reps.parse(text).map(\.count) == .success(count))
  }

  @Test(arguments: [
    ("", RepsRefusal.empty), (" ", .empty), ("1.5", .notANumber), ("ten", .notANumber),
    ("１０", .notANumber), ("-1", .notANumber), ("0", .outOfRange), ("1000", .outOfRange),
    ("99999999999999999999999", .outOfRange),
  ])
  func refusesOtherText(text: String, refusal: RepsRefusal) {
    #expect(Reps.parse(text) == .failure(refusal))
  }
}
