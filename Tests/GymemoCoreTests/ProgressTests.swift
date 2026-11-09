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

  @Test func summarizesLoggedExercisesFromTheMostRecent() throws {
    var builder = try sample()
    let summaries = builder.log.exerciseSummaries
    #expect(summaries.map(\.exercise.id) == [exerciseID(2), exerciseID(1)])
    #expect(summaries.map(\.lastDay.iso) == ["2026-11-09", "2026-11-09"])
    #expect(summaries.map(\.best?.score.text) == ["10", "82.3"])
    try builder.apply(.setExerciseArchived(id: exerciseID(2), isArchived: true))
    #expect(builder.log.exerciseSummaries.map(\.exercise.id) == [exerciseID(2), exerciseID(1)])
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
