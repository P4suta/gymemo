import Foundation
import Testing

@testable import GymemoCore

@Suite struct TimedActivityTests {
  @Test func aWalkAloneMakesTheDayAppearInHistory() throws {
    let day = try #require(LocalDay(iso: "2026-11-19"))
    let duration = try #require(ActivityDuration(minutes: 20))
    let walk = LoggedActivity(
      id: LoggedActivityID(UUID()), activityID: .walking, day: day, duration: duration,
      distance: nil)
    let saved = try TrainingLog.empty.apply(.record(walk)).get()
    #expect(saved.log.activities.records(on: day) == [walk])
    #expect(saved.log.history.first?.activities == [walk])
    #expect(saved.log.trainingDays == [day])
    #expect(saved.log.weeklyTrainingDays(through: day, weeks: 1).first?.days == 1)

    let note = try saved.log.apply(.writeMemo(day: day, text: "Walked home")).get()
    #expect(note.log.activities.records(on: day) == [walk])
    let deleted = try note.log.apply(.delete(walk.id)).get()
    #expect(deleted.log.activities.records(on: day).isEmpty)
    #expect(deleted.log.trainingDays.isEmpty)
    #expect(deleted.log.history.first?.memo?.text == "Walked home")
  }

  @Test func shortcutsAndFileBoundariesUseCanonicalUnits() throws {
    let load = try WeightUnit.pounds.parse("100").get()
    #expect(load.hundredths == 4_536)
    #expect(WeightUnit.pounds.hundredths(for: load) == 10_000)
    #expect(WeightUnit.pounds.parse("0.01") == .failure(.outOfRange))
    let tenPounds = WeightUnit.pounds.stepped(from: .bodyweight, by: 2)
    #expect(WeightUnit.pounds.hundredths(for: tenPounds) == 1_000)
    let mile = try #require(DistanceUnit.miles.parse("1"))
    #expect(mile.meters == 1_609)
    #expect(DistanceUnit.miles.thousandths(for: mile) == 1_000)
  }

  @Test func manualActivitiesSurviveBackupAndPreserveDistanceEligibility() throws {
    let day = try #require(LocalDay(iso: "2026-11-19"))
    let duration = try #require(ActivityDuration(minutes: 20))
    let distance = try #require(ActivityDistance(meters: 1_500))
    let id = TimedActivityID(UUID())
    let named = try TrainingLog.empty.apply(
      .add(id: id, name: "Stretching", tracksDistance: false)
    ).get().log
    let stretching = LoggedActivity(
      id: LoggedActivityID(UUID()), activityID: id, day: day, duration: duration, distance: distance
    )
    #expect(named.apply(.record(stretching)) == .failure(.unexpectedDistance))
    let walk = LoggedActivity(
      id: LoggedActivityID(UUID()), activityID: .walking, day: day, duration: duration,
      distance: distance)
    let saved = try named.apply(.record(walk)).get().log
    #expect(saved.apply(.record(walk)) == .failure(.duplicateIdentifier))
    #expect(Backup.read(Backup.write(saved)) == .success(saved))
    let csv = CSVExport.writeActivities(
      saved,
      labels: ActivityCSVLabels(
        day: "Date", activity: "Activity", minutes: "min", meters: "m", walking: "Walking"))
    #expect(
      String(decoding: csv.dropFirst(3), as: UTF8.self)
        == "Date,Activity,min,m\r\n2026-11-19,Walking,20,1500\r\n")
  }
}
