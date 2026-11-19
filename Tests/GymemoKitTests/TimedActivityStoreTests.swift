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
}
