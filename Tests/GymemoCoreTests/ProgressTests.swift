import GymemoCore
import GymemoTestSupport
import Testing

@Suite struct ProgressTests {
  private func sample() throws -> LogBuilder {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    try builder.exercise(2, "懸垂", .back)
    try builder.exercise(3, "スクワット", .legs)
    try builder.set(1, "2026-11-02", "60", 10)
    try builder.set(1, "2026-11-02", "70", 3)
    try builder.set(1, "2026-11-05", "65", 8)
    try builder.set(1, "2026-11-05", "60", 10)
    try builder.set(2, "2026-11-05", "0", 8)
    try builder.set(1, "2026-11-09", "60", 10)
    try builder.set(2, "2026-11-09", "0", 10)
    try builder.set(2, "2026-11-09", "0", 6)
    return builder
  }

  /// The heaviest set of an exercise whose sets are each a day, a weight, and a repetition count.
  private func heaviest(_ rows: (String, String, Int)...) throws -> SetID? {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    for (day, weight, count) in rows {
      try builder.set(1, day, weight, count)
    }
    return try #require(builder.log.progress(of: exerciseID(1))).heaviest?.id
  }

  @Test func plotsTheBestEstimateOfEachDay() throws {
    let progress = try #require(try sample().log.progress(of: exerciseID(1)))
    #expect(progress.kind == .oneRepMax)
    #expect(progress.points.map(\.day.iso) == ["2026-11-02", "2026-11-05", "2026-11-09"])
    #expect(progress.points.map(\.best.id) == [setID(1), setID(3), setID(6)])
    #expect(progress.points.map(\.score.text) == ["80", "82.3", "80"])
    #expect(progress.best?.best.id == setID(3))
    #expect(progress.heaviest?.id == setID(2))
    #expect(progress.sessions.map(\.day.iso) == ["2026-11-09", "2026-11-05", "2026-11-02"])
    #expect(progress.sessions[1].sets.map(\.id) == [setID(3), setID(4)])
  }

  @Test func keepsTheEarliestDayWhenScoresTie() throws {
    var builder = try sample()
    try builder.set(1, "2026-11-12", "65", 8)
    let progress = try #require(builder.log.progress(of: exerciseID(1)))
    #expect(progress.best?.day.iso == "2026-11-05")
  }

  @Test func ordersPointsAndSessionsByDayWhateverTheOrderOfLogging() throws {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    try builder.set(1, "2026-11-09", "60", 10)
    try builder.set(1, "2026-11-02", "60", 10)
    try builder.set(1, "2026-11-05", "60", 10)
    let progress = try #require(builder.log.progress(of: exerciseID(1)))
    #expect(progress.points.map(\.day.iso) == ["2026-11-02", "2026-11-05", "2026-11-09"])
    #expect(progress.sessions.map(\.day.iso) == ["2026-11-09", "2026-11-05", "2026-11-02"])
    #expect(progress.best?.day.iso == "2026-11-02")
  }

  @Test func ranksTheHeaviestSetByWeightBeforeRepetitions() throws {
    #expect(try heaviest(("2026-11-05", "70", 3), ("2026-11-09", "60", 10)) == setID(1))
    #expect(try heaviest(("2026-11-05", "60", 10), ("2026-11-09", "70", 3)) == setID(2))
    #expect(try heaviest(("2026-11-09", "70", 3), ("2026-11-05", "60", 10)) == setID(1))
    #expect(try heaviest(("2026-11-09", "60", 10), ("2026-11-05", "70", 3)) == setID(2))
  }

  @Test func breaksATieOnTheHeaviestWeightByRepetitions() throws {
    #expect(try heaviest(("2026-11-05", "60", 10), ("2026-11-09", "60", 8)) == setID(1))
    #expect(try heaviest(("2026-11-05", "60", 8), ("2026-11-09", "60", 10)) == setID(2))
    #expect(try heaviest(("2026-11-09", "60", 10), ("2026-11-05", "60", 8)) == setID(1))
    #expect(try heaviest(("2026-11-09", "60", 8), ("2026-11-05", "60", 10)) == setID(2))
  }

  @Test func breaksATieOnWeightAndRepetitionsByTheEarliestDayThenTheFirstSet() throws {
    #expect(try heaviest(("2026-11-05", "60", 10), ("2026-11-09", "60", 10)) == setID(1))
    #expect(try heaviest(("2026-11-09", "60", 10), ("2026-11-05", "60", 10)) == setID(2))
    #expect(try heaviest(("2026-11-09", "60", 10), ("2026-11-09", "60", 10)) == setID(1))
  }

  @Test func plotsRepetitionsForAnExerciseWithoutAddedWeight() throws {
    let progress = try #require(try sample().log.progress(of: exerciseID(2)))
    #expect(progress.kind == .reps)
    #expect(progress.points.map(\.score.text) == ["8", "10"])
    #expect(progress.points.map(\.best.id) == [setID(5), setID(7)])
    #expect(progress.best?.day.iso == "2026-11-09")
    #expect(progress.heaviest == nil)
  }

  @Test func plotsOnlyWeightedSetsOnceAnExerciseHasAddedWeight() throws {
    var builder = try sample()
    try builder.set(2, "2026-11-12", "10", 5)
    let progress = try #require(builder.log.progress(of: exerciseID(2)))
    #expect(progress.kind == .oneRepMax)
    #expect(progress.points.map(\.day.iso) == ["2026-11-12"])
    #expect(progress.sessions.count == 3)
  }

  @Test func hasNoPointsBeforeTheFirstSetAndNoProgressForAnUnknownExercise() throws {
    let log = try sample().log
    let unused = try #require(log.progress(of: exerciseID(3)))
    #expect(unused.points.isEmpty)
    #expect(unused.best == nil)
    #expect(unused.sessions.isEmpty)
    #expect(log.progress(of: exerciseID(9)) == nil)
  }

  @Test func keepsOnlyThePointsSinceADay() throws {
    let progress = try #require(try sample().log.progress(of: exerciseID(1)))
    #expect(
      progress.points(since: try day("2026-11-05")).map(\.day.iso) == ["2026-11-05", "2026-11-09"])
    #expect(progress.points(since: nil).count == 3)
  }

  private func measuredProgress(
    _ offsets: [Int], scores: [Int], kind: ScoreKind = .oneRepMax
  ) throws -> ExerciseProgress {
    let start = try day("2026-01-01")
    var builder = LogBuilder()
    try builder.exercise(1, "Bench Press", .chest)
    for (offset, score) in zip(offsets, scores) {
      let session = try #require(start.adding(days: offset))
      let (weight, reps) = kind == .oneRepMax ? (String(score), 1) : ("0", score)
      try builder.set(1, session.iso, weight, reps)
    }
    return try #require(builder.log.progress(of: exerciseID(1)))
  }

  @Test(arguments: [0, 1, 2, 3, 4], [1, 900])
  func fitsAnIrregularLinearTrendThroughOneExtremeScore(index: Int, extreme: Int) throws {
    let offsets = [0, 1, 3, 10, 12]
    let expected = offsets.map { 50 + 2 * $0 }
    var scores = expected
    scores[index] = extreme
    let progress = try measuredProgress(offsets, scores: scores)
    let trend = progress.trend(since: nil)
    #expect(progress.points.map(\.score.value) == scores.map(Double.init))
    #expect(trend.count == 1)
    #expect(trend.flatMap(\.points).map(\.day) == progress.points.map(\.day))
    #expect(trend.flatMap(\.points).map(\.value) == expected.map(Double.init))
  }

  @Test func needsFiveDaysToShowATrend() throws {
    let sparse = try measuredProgress([0, 7, 14, 21], scores: [50, 55, 60, 65])
    let enough = try measuredProgress([0, 7, 14, 21, 28], scores: [50, 55, 60, 65, 70])
    #expect(sparse.trend(since: nil).isEmpty)
    #expect(enough.trend(since: nil).first?.points.count == 5)
  }

  @Test func breaksTheTrendAcrossLongGapsAndKeepsSharedValuesAcrossRanges() throws {
    let offsets = [0, 3, 6, 9, 12, 54, 57, 60, 63, 66, 109, 112, 115, 118, 121]
    let progress = try measuredProgress(offsets, scores: offsets.map { 50 + $0 })
    let full = progress.trend(since: nil)
    let cropped = progress.trend(since: progress.points[8].day)
    let oneDayBeforeTheBreak = progress.trend(since: progress.points[9].day)
    #expect(full.map(\.points.count) == [10, 5])
    #expect(cropped.map(\.points.count) == [2, 5])
    #expect(cropped.first?.points == full.first.map { Array($0.points.suffix(2)) })
    #expect(cropped.last == full.last)
    #expect(oneDayBeforeTheBreak == Array(full.dropFirst()))
  }

  @Test func followsASustainedChangeWithoutPullingInRemoteScores() throws {
    let scores = Array(repeating: 30, count: 9) + Array(repeating: 70, count: 9)
    let progress = try measuredProgress(Array(scores.indices), scores: scores)
    let trend = try #require(progress.trend(since: nil).first)
    #expect(trend.points.first?.value == 30)
    #expect(trend.points.last?.value == 70)
  }

  @Test func keepsTheBodyweightTrendWithinTheRepetitionBounds() throws {
    let offsets = [0, 1, 2, 3, 4]
    let lower = try measuredProgress(offsets, scores: [999, 1, 2, 3, 4], kind: .reps)
    let upper = try measuredProgress(offsets, scores: [996, 997, 998, 999, 1], kind: .reps)
    #expect(lower.trend(since: nil).flatMap(\.points).map(\.value) == [1, 1, 2, 3, 4])
    #expect(upper.trend(since: nil).flatMap(\.points).map(\.value) == [996, 997, 998, 999, 999])
  }

  @Test func summarizesLoggedExercisesFromTheMostRecent() throws {
    var builder = try sample()
    let summaries = builder.log.exerciseSummaries
    #expect(summaries.map(\.exercise.id) == [exerciseID(2), exerciseID(1)])
    #expect(summaries.map(\.lastDay.iso) == ["2026-11-09", "2026-11-09"])
    #expect(summaries.map(\.best?.score.text) == ["10", "82.3"])
    try builder.apply(.setExerciseArchived(id: exerciseID(2), isArchived: true))
    #expect(builder.log.exerciseSummaries.map(\.exercise.id) == [exerciseID(2), exerciseID(1)])
  }

  @Test func datesASummaryByTheLatestDayWhateverTheOrderOfLogging() throws {
    var builder = try sample()
    try builder.set(2, "2026-11-01", "0", 9)
    try builder.set(1, "2026-11-12", "60", 10)
    try builder.set(1, "2026-11-03", "60", 10)
    let summaries = builder.log.exerciseSummaries
    #expect(summaries.map(\.exercise.id) == [exerciseID(1), exerciseID(2)])
    #expect(summaries.map(\.lastDay.iso) == ["2026-11-12", "2026-11-09"])
  }
}

@Suite struct WeeklyTrainingDaysTests {
  @Test func countsDistinctTrainingDaysInWeeksThatStartOnMonday() throws {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    try builder.set(1, "2026-10-25", "60", 10)
    try builder.set(1, "2026-10-26", "60", 10)
    try builder.set(1, "2026-11-01", "60", 10)
    try builder.set(1, "2026-11-02", "60", 10)
    try builder.set(1, "2026-11-02", "60", 8)
    try builder.set(1, "2026-11-09", "60", 10)
    try builder.set(1, "2026-11-11", "60", 10)
    try builder.apply(.writeMemo(day: try day("2026-11-10"), text: "休み"))
    let weeks = builder.log.weeklyTrainingDays(through: try day("2026-11-11"), weeks: 4)
    #expect(weeks.map(\.start.iso) == ["2026-10-19", "2026-10-26", "2026-11-02", "2026-11-09"])
    #expect(weeks.map(\.days) == [1, 2, 1, 2])
  }

  @Test func coversExactlyTheRequestedWeeks() throws {
    let today = try day("2026-11-15")
    #expect(TrainingLog.empty.weeklyTrainingDays(through: today, weeks: 12).count == 12)
    #expect(
      TrainingLog.empty.weeklyTrainingDays(through: today, weeks: 12).allSatisfy { $0.days == 0 })
    #expect(
      TrainingLog.empty.weeklyTrainingDays(through: today, weeks: 1).map(\.start.iso) == [
        "2026-11-09"
      ])
    #expect(TrainingLog.empty.weeklyTrainingDays(through: today, weeks: 0).isEmpty)
    #expect(
      TrainingLog.empty.weeklyTrainingDays(through: .earliest, weeks: 3).map(\.start) == [.earliest]
    )
  }
}
