import GymemoCore
import GymemoTestSupport
import Testing

@Suite struct DayQueriesTests {
  private func sample() throws -> LogBuilder {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    try builder.exercise(2, "スクワット", .legs)
    try builder.exercise(3, "懸垂", .back)
    try builder.set(1, "2026-11-05", "60", 10)
    try builder.set(1, "2026-11-05", "60", 8)
    try builder.set(2, "2026-11-07", "100", 5)
    try builder.set(2, "2026-11-09", "102.5", 5)
    try builder.set(1, "2026-11-09", "62.5", 8)
    try builder.set(2, "2026-11-09", "102.5", 4)
    try builder.set(1, "2026-11-12", "65", 5)
    return builder
  }

  @Test func groupsADayByExerciseInTheOrderOfTheirFirstSets() throws {
    let log = try sample().log
    let sections = log.sections(on: try day("2026-11-09"))
    #expect(sections.map(\.exercise.id) == [exerciseID(2), exerciseID(1)])
    #expect(sections.map { $0.sets.map(\.id) } == [[setID(4), setID(6)], [setID(5)]])
    #expect(log.sections(on: try day("2026-11-06")).isEmpty)
  }

  @Test func findsTheLatestEarlierDayOfAnExercise() throws {
    let log = try sample().log
    let previous = try #require(
      log.previousSession(of: exerciseID(1), before: try day("2026-11-09")))
    #expect(previous.day == (try day("2026-11-05")))
    #expect(previous.sets.map(\.id) == [setID(1), setID(2)])
    let later = try #require(log.previousSession(of: exerciseID(1), before: try day("2026-11-12")))
    #expect(later.day == (try day("2026-11-09")))
    #expect(log.previousSession(of: exerciseID(1), before: try day("2026-11-05")) == nil)
    #expect(log.previousSession(of: exerciseID(3), before: try day("2026-11-09")) == nil)
  }

  @Test func suggestsTheLastSetOfTheDayAndOtherwiseTheFirstSetOfThePreviousDay() throws {
    let log = try sample().log
    let sameDay = try #require(log.suggestedEntry(for: exerciseID(2), on: try day("2026-11-09")))
    #expect(sameDay.weight.text == "102.5")
    #expect(sameDay.reps.count == 4)
    let nextDay = try #require(log.suggestedEntry(for: exerciseID(1), on: try day("2026-11-10")))
    #expect(nextDay.weight.text == "62.5")
    #expect(nextDay.reps.count == 8)
    let afterTwoSets = try #require(
      log.suggestedEntry(for: exerciseID(1), on: try day("2026-11-06")))
    #expect(afterTwoSets.weight.text == "60")
    #expect(afterTwoSets.reps.count == 10)
    #expect(log.suggestedEntry(for: exerciseID(3), on: try day("2026-11-09")) == nil)
    #expect(log.suggestedEntry(for: exerciseID(1), on: try day("2026-11-01")) == nil)
  }

  @Test func listsRecordedDaysFromNewestToOldestWithTheirContents() throws {
    var builder = try sample()
    try builder.apply(.writeMemo(day: try day("2026-11-08"), text: "休み"))
    try builder.apply(.writeMemo(day: try day("2026-11-09"), text: "調子がいい"))
    let history = builder.log.history
    #expect(
      history.map(\.day.iso) == [
        "2026-11-12", "2026-11-09", "2026-11-08", "2026-11-07", "2026-11-05",
      ])
    #expect(history[1].exerciseNames.map(\.text) == ["スクワット", "ベンチプレス"])
    #expect(history[1].setCount == 3)
    #expect(history[1].memo?.text == "調子がいい")
    #expect(history[2].exerciseNames.isEmpty)
    #expect(history[2].setCount == 0)
    #expect(history[2].memo?.text == "休み")
    #expect(TrainingLog.empty.history.isEmpty)
  }

  @Test func ranksRecentlyLoggedExercisesFirstAndSkipsArchivedOnes() throws {
    var builder = try sample()
    #expect(builder.log.recentExercises(limit: 5).map(\.id) == [exerciseID(1), exerciseID(2)])
    #expect(builder.log.recentExercises(limit: 1).map(\.id) == [exerciseID(1)])
    #expect(builder.log.recentExercises(limit: 0).isEmpty)
    try builder.set(3, "2026-11-12", "0", 12)
    #expect(
      builder.log.recentExercises(limit: 5).map(\.id) == [
        exerciseID(3), exerciseID(1), exerciseID(2),
      ])
    try builder.apply(.setExerciseArchived(id: exerciseID(3), isArchived: true))
    #expect(builder.log.recentExercises(limit: 5).map(\.id) == [exerciseID(1), exerciseID(2)])
  }

  @Test func groupsSelectableExercisesByBodyPart() throws {
    var builder = try sample()
    try builder.exercise(4, "ラットプルダウン", .back)
    try builder.apply(.setExerciseArchived(id: exerciseID(2), isArchived: true))
    let groups = builder.log.selectableExercises
    #expect(groups.map(\.bodyPart) == [.chest, .back])
    #expect(
      groups.map { $0.exercises.map(\.id) } == [[exerciseID(1)], [exerciseID(3), exerciseID(4)]])
    let all = builder.log.exercisesByBodyPart
    #expect(all.map(\.bodyPart) == [.chest, .back, .legs])
  }
}
