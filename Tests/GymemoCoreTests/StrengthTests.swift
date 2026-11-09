import GymemoCore
import GymemoTestSupport
import Testing

@Suite struct OneRepMaxTests {
  @Test(arguments: [
    ("60", 10, "80"), ("100", 1, "100"), ("62.5", 8, "79.2"), ("0.5", 3, "0.6"),
    ("100", 2, "106.7"), ("999.99", 999, "34299.7"), ("20", 30, "40"),
  ])
  func estimatesFromWeightAndRepetitions(weight: String, count: Int, text: String) throws {
    let estimate = OneRepMax.estimate(weight: try kilograms(weight), reps: try reps(count))
    #expect(estimate?.text == text)
  }

  @Test func hasNoEstimateWithoutAddedWeight() throws {
    #expect(OneRepMax.estimate(weight: .bodyweight, reps: try reps(10)) == nil)
  }

  @Test func growsWithEitherMoreWeightOrMoreRepetitions() throws {
    for hundredths in stride(from: 250, through: 30_000, by: 250) {
      for count in 1...30 {
        let weight = try #require(Weight(hundredths: hundredths))
        let heavier = try #require(Weight(hundredths: hundredths + 25))
        let here = try #require(OneRepMax.estimate(weight: weight, reps: try reps(count)))
        let moreWeight = try #require(OneRepMax.estimate(weight: heavier, reps: try reps(count)))
        let moreReps = try #require(OneRepMax.estimate(weight: weight, reps: try reps(count + 1)))
        if !(here < moreWeight && here < moreReps) {
          Issue.record("The estimate fell after \(weight.text) kg for \(count)")
          return
        }
      }
    }
  }

  @Test func exposesKilogramsForPlotting() throws {
    let estimate = try #require(
      OneRepMax.estimate(weight: try kilograms("60"), reps: try reps(10)))
    #expect(estimate.kilograms == 80)
  }
}

@Suite struct PersonalBestTests {
  @Test func marksSetsThatBeatEveryEarlierSetOfTheExercise() throws {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    try builder.set(1, "2026-11-02", "60", 10)
    try builder.set(1, "2026-11-02", "70", 5)
    let equal = try builder.set(1, "2026-11-05", "60", 10)
    let better = try builder.set(1, "2026-11-05", "62.5", 10)
    let lower = try builder.set(1, "2026-11-05", "62.5", 8)
    let best = try builder.set(1, "2026-11-05", "65", 10)
    let marked = builder.log.personalBests(on: try day("2026-11-05"))
    #expect(marked == [better, best])
    #expect(!marked.contains(equal) && !marked.contains(lower))
  }

  @Test func marksNothingOnTheFirstDayOfAnExercise() throws {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    try builder.set(1, "2026-11-02", "60", 10)
    try builder.set(1, "2026-11-02", "80", 10)
    #expect(builder.log.personalBests(on: try day("2026-11-02")).isEmpty)
    #expect(builder.log.personalBests(on: try day("2026-11-03")).isEmpty)
  }

  @Test func ignoresLaterDaysAndOtherExercises() throws {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    try builder.exercise(2, "スクワット", .legs)
    try builder.set(1, "2026-11-02", "60", 10)
    try builder.set(2, "2026-11-02", "140", 5)
    try builder.set(1, "2026-11-09", "100", 5)
    let middle = try builder.set(1, "2026-11-05", "62.5", 10)
    let squat = try builder.set(2, "2026-11-05", "100", 5)
    let marked = builder.log.personalBests(on: try day("2026-11-05"))
    #expect(marked == [middle])
    #expect(!marked.contains(squat))
  }

  @Test func comparesBodyweightSetsByRepetitionsApartFromWeightedSets() throws {
    var builder = LogBuilder()
    try builder.exercise(1, "懸垂", .back)
    try builder.set(1, "2026-11-02", "0", 8)
    try builder.set(1, "2026-11-02", "10", 3)
    let fewer = try builder.set(1, "2026-11-05", "0", 7)
    let more = try builder.set(1, "2026-11-05", "0", 9)
    let weighted = try builder.set(1, "2026-11-05", "10", 4)
    let light = try builder.set(1, "2026-11-05", "5", 3)
    let marked = builder.log.personalBests(on: try day("2026-11-05"))
    #expect(marked == [more, weighted])
    #expect(!marked.contains(fewer) && !marked.contains(light))
  }
}
