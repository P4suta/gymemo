import Foundation
import GymemoCore
import Testing

@testable import GymemoKit

@Suite struct TimedActivityStoreTests {
  @Test func reopeningAndReplacingTheLogKeepsActivityRowsConsistent() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("activities.sqlite")
    let day = try #require(LocalDay(iso: "2026-11-19"))
    let duration = try #require(ActivityDuration(minutes: 20))
    let revisedDuration = try #require(ActivityDuration(minutes: 30))
    let distance = try #require(ActivityDistance(meters: 1_500))
    let store = try TrainingLogStore(url: file, starter: .empty)
    let named = try store.load().apply(
      .add(id: TimedActivityID(UUID()), name: "Stretching", tracksDistance: false)
    ).get()
    try store.apply(named.changes)
    let walk = LoggedActivity(
      id: LoggedActivityID(UUID()), activityID: .walking, day: day, duration: duration,
      distance: distance)
    let added = try named.log.apply(.record(walk)).get()
    try store.apply(added.changes)
    let edited = try added.log.apply(.edit(walk.id, duration: revisedDuration, distance: nil)).get()
    try store.apply(edited.changes)
    let reopened = try TrainingLogStore(url: file, starter: .empty)
    #expect(try reopened.load() == edited.log)
    try reopened.apply([.replaceAll(added.log)])
    #expect(try reopened.load() == added.log)
    try reopened.apply([.replaceAll(.empty)])
    #expect(try reopened.load() == .empty)
  }

  @Test(arguments: [
    "UPDATE timed_activity SET name = 'Walk' WHERE position = -1",
    "UPDATE timed_activity SET tracks_distance = 0 WHERE position = -1",
    "UPDATE timed_activity SET id = '67796D65-6D6F-4000-8000-000000000001' WHERE position = -1",
  ])
  func refusesAMalformedBuiltInWalkingDefinition(statement: String) throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("activities.sqlite")
    let store = try TrainingLogStore(url: file, starter: .empty)
    let database = try SQLiteDatabase(url: file)
    try database.execute(statement)
    try database.close()
    #expect(throws: StoreFailure.corruptRow(table: "timed_activity")) { try store.load() }
  }
}
