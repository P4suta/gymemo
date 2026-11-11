import Foundation
import GymemoCore
import GymemoTestSupport
import Testing

@testable import GymemoKit

@Suite struct TrainingLogStoreTests {
  private func bench(in log: TrainingLog) throws -> Exercise {
    try #require(log.exercises.first)
  }

  private func logged(_ number: UInt32, _ exercise: Exercise) throws -> LoggedSet {
    LoggedSet(
      id: setID(number), exerciseID: exercise.id,
      day: try #require(LocalDay(iso: "2026-11-09")),
      weight: try #require(Weight(hundredths: 6000)), reps: try #require(Reps(10)))
  }

  @Test func aNewFileStartsWithTheStarterLogAndAnExistingFileKeepsItsOwn() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("log.sqlite")
    let first = try TrainingLogStore(url: file, starter: .starter)
    #expect(try first.load() == .starter)
    let removed = try bench(in: .starter)
    try first.apply([.removeExercise(removed.id)])
    let second = try TrainingLogStore(url: file, starter: .starter)
    let reloaded = try second.load()
    #expect(reloaded.exercises.count == TrainingLog.starter.exercises.count - 1)
    #expect(reloaded.exercise(removed.id) == nil)
    #expect(
      try TrainingLogStore(url: directory.file("empty.sqlite"), starter: .empty).load() == .empty)
  }

  @Test(arguments: [21, 22, 23, 24] as [UInt64])
  func aReopenedFileEqualsTheLogAfterEveryCommandSequence(seed: UInt64) throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("log.sqlite")
    var store = try TrainingLogStore(url: file, starter: .empty)
    var generator = SeededGenerator(seed: seed)
    var log = TrainingLog.empty
    var accepted = 0
    for step in 0..<400 {
      let command = RandomCommand.next(using: &generator)
      guard case .success(let transition) = log.apply(command) else { continue }
      accepted += 1
      try store.apply(transition.changes)
      log = transition.log
      if step % 40 == 0 { store = try TrainingLogStore(url: file, starter: .starter) }
      if try store.load() != log {
        Issue.record("Seed \(seed) left the file behind the log at step \(step) with \(command)")
        return
      }
    }
    #expect(accepted > 80)
  }

  @Test func replacesEverythingWithALargeLog() throws {
    let exercise = try bench(in: .starter)
    var sets: [LoggedSet] = []
    for number in 0..<5000 {
      sets.append(
        LoggedSet(
          id: setID(UInt32(number)), exerciseID: exercise.id,
          day: try #require(LocalDay.earliest.adding(days: 46_000 + number / 20)),
          weight: try #require(Weight(hundredths: number % 30_000)),
          reps: try #require(Reps(number % 20 + 1))))
    }
    let memoDay = try #require(LocalDay(iso: "2026-11-09"))
    let memo = try #require(try Memo.parse("一行目\n二行目 \"引用\"").get())
    let large = try TrainingLog.make(
      exercises: TrainingLog.starter.exercises, sets: sets, memos: [memoDay: memo]
    ).get()
    let directory = try TemporaryDirectory()
    let file = directory.file("log.sqlite")
    let store = try TrainingLogStore(url: file, starter: .starter)
    try store.apply([.putSet(try logged(900_000, exercise))])
    try store.apply([.replaceAll(large)])
    #expect(try store.load() == large)
    #expect(try TrainingLogStore(url: file, starter: .empty).load() == large)
  }

  @Test func aFailedChangeLeavesNothingOfItsBatch() throws {
    let directory = try TemporaryDirectory()
    let store = try TrainingLogStore(url: directory.file("log.sqlite"), starter: .starter)
    let exercise = try bench(in: .starter)
    try store.apply([.putSet(try logged(1, exercise))])
    let before = try store.load()
    #expect(throws: StoreFailure.self) {
      try store.apply([.putSet(try logged(2, exercise)), .removeExercise(exercise.id)])
    }
    #expect(try store.load() == before)
    let stray = LoggedSet(
      id: setID(3), exerciseID: exerciseID(404), day: try #require(LocalDay(iso: "2026-11-09")),
      weight: .bodyweight, reps: .one)
    #expect(throws: StoreFailure.self) { try store.apply([.putSet(stray)]) }
    #expect(try store.load() == before)
  }

  @Test func refusesAFileWithAnotherSchemaNumber() throws {
    let directory = try TemporaryDirectory()
    let newer = directory.file("newer.sqlite")
    _ = try TrainingLogStore(url: newer, starter: .starter)
    do {
      let database = try SQLiteDatabase(url: newer)
      try database.execute("PRAGMA user_version = 3")
      try database.close()
    }
    #expect(throws: StoreFailure.unsupportedSchema(version: 3)) {
      try TrainingLogStore(url: newer, starter: .starter)
    }
    let foreign = directory.file("foreign.sqlite")
    do {
      let database = try SQLiteDatabase(url: foreign)
      try database.execute("CREATE TABLE note (text TEXT)")
      try database.close()
    }
    #expect(throws: StoreFailure.unsupportedSchema(version: 0)) {
      try TrainingLogStore(url: foreign, starter: .starter)
    }
  }

  @Test func refusesAFileThatIsNotADatabase() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("garbage.sqlite")
    try Data(repeating: 0x5A, count: 4096).write(to: file)
    #expect {
      try TrainingLogStore(url: file, starter: .starter)
    } throws: { error in
      if case .sqlite = error as? StoreFailure { true } else { false }
    }
    #expect {
      try TrainingLogStore(url: directory.file("absent/log.sqlite"), starter: .starter)
    } throws: { error in
      if case .sqlite = error as? StoreFailure { true } else { false }
    }
  }

  @Test(arguments: [
    ("UPDATE exercise SET body_part = 'wings' WHERE position = 0", "exercise"),
    ("UPDATE exercise SET id = 'not-a-uuid' WHERE position = 1", "exercise"),
    ("UPDATE exercise SET name = '  ' WHERE position = 2", "exercise"),
    ("UPDATE logged_set SET day = '2026-02-30'", "logged_set"),
    ("UPDATE logged_set SET id = 'x'", "logged_set"),
    ("INSERT INTO day_memo (day, text) VALUES ('2026-11-09', '')", "day_memo"),
    ("INSERT INTO day_memo (day, text) VALUES ('11/09', 'a')", "day_memo"),
  ])
  func refusesRowsThatTheCoreWouldNotBuild(statement: String, table: String) throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("log.sqlite")
    let store = try TrainingLogStore(url: file, starter: .starter)
    try store.apply([.putSet(try logged(1, try bench(in: .starter)))])
    let database = try SQLiteDatabase(url: file)
    try database.execute("PRAGMA foreign_keys = OFF")
    try database.execute(statement)
    try database.close()
    #expect(throws: StoreFailure.corruptRow(table: table)) {
      try TrainingLogStore(url: file, starter: .starter).load()
    }
  }

  @Test(arguments: [
    "UPDATE logged_set SET reps = 0", "UPDATE logged_set SET reps = 1000",
    "UPDATE logged_set SET weight_hundredths = -1",
    "UPDATE logged_set SET weight_hundredths = 100000",
    "UPDATE logged_set SET reps = 'ten'", "UPDATE exercise SET archived = 2",
    "UPDATE exercise SET name = (SELECT name FROM exercise WHERE position = 1) WHERE position = 0",
  ])
  func theFileItselfRefusesValuesOutsideTheirRanges(statement: String) throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("log.sqlite")
    let store = try TrainingLogStore(url: file, starter: .starter)
    try store.apply([.putSet(try logged(1, try bench(in: .starter)))])
    let database = try SQLiteDatabase(url: file)
    #expect(throws: StoreFailure.self) { try database.execute(statement) }
  }
}

@Suite struct LocalDayCalendarTests {
  @Test func readsTheDayOfAnInstantInATimeZone() throws {
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-09T15:30:00Z"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let utc = try #require(TimeZone(identifier: "UTC"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    #expect(LocalDay(date: instant, timeZone: tokyo)?.iso == "2026-11-10")
    #expect(LocalDay(date: instant, timeZone: utc)?.iso == "2026-11-09")
    #expect(LocalDay(date: instant, timeZone: losAngeles)?.iso == "2026-11-09")
    #expect(LocalDay(date: .distantPast, timeZone: utc) == nil)
    #expect(LocalDay(date: .distantFuture, timeZone: utc) == nil)
  }

  @Test func keepsTheDeviceDayInsideTheSupportedYears() throws {
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-09T15:30:00Z"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    #expect(LocalDay.nearest(to: instant, in: tokyo).iso == "2026-11-10")
    #expect(LocalDay.nearest(to: .distantPast, in: tokyo) == .earliest)
    #expect(LocalDay.nearest(to: .distantFuture, in: tokyo) == .latest)
  }

  @Test(arguments: [-64_800, -46_800, -43_201, -43_200, 0, 50_400, 64_800])
  func choosesTheNearerEndJustOutsideTheSupportedYears(secondsFromGMT: Int) throws {
    let zone = try #require(TimeZone(secondsFromGMT: secondsFromGMT))
    let offset = TimeInterval(secondsFromGMT)
    // The supported days start and end at these instants on a clock that runs this far ahead of UTC.
    let start = LocalDay.earliest.noonUTC.addingTimeInterval(-43_200 - offset)
    let end = LocalDay.latest.noonUTC.addingTimeInterval(43_200 - offset)
    #expect(LocalDay.nearest(to: start.addingTimeInterval(-1), in: zone) == .earliest)
    #expect(LocalDay.nearest(to: start, in: zone) == .earliest)
    #expect(
      LocalDay.nearest(to: start.addingTimeInterval(86_400), in: zone)
        == LocalDay.earliest.adding(days: 1))
    #expect(
      LocalDay.nearest(to: end.addingTimeInterval(-86_401), in: zone)
        == LocalDay.latest.adding(days: -1))
    #expect(LocalDay.nearest(to: end.addingTimeInterval(-1), in: zone) == .latest)
    #expect(LocalDay.nearest(to: end, in: zone) == .latest)
  }

  @Test(arguments: [1900, 2026, 2200])
  func hasNoDayForASupportedYearNumberBeforeTheCommonEra(year: Int) throws {
    let utc = try #require(TimeZone(identifier: "UTC"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let instant = try #require(
      calendar.date(from: DateComponents(era: 0, year: year, month: 6, day: 15, hour: 12)))
    #expect(LocalDay(date: instant, timeZone: utc) == nil)
    #expect(LocalDay.nearest(to: instant, in: utc) == .earliest)
  }

  @Test func givesBackItsOwnDayAtNoonInUTC() throws {
    let utc = try #require(TimeZone(identifier: "UTC"))
    for number in LocalDay.earliest.dayNumber...LocalDay.latest.dayNumber {
      let day = try #require(LocalDay(dayNumber: number))
      if LocalDay(date: day.noonUTC, timeZone: utc) != day {
        Issue.record("\(day.iso) did not survive its own noon")
        return
      }
    }
  }
}
