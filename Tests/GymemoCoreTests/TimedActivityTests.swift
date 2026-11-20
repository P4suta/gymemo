import Foundation
import GymemoTestSupport
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

  @Test func acceptsTheActivityDefinitionLimitAndRefusesOneMore() throws {
    let definitions = try (0...UInt32(TrainingLog.maximumExercises)).map { number in
      let name = try ExerciseName.parse("Activity \(number)").get()
      return try #require(
        TimedActivity(id: TimedActivityID(uuid(number)), name: name, tracksDistance: false))
    }
    let extra = try #require(definitions.last)
    let full = try ActivityLog.make(
      customActivities: Array(definitions.dropLast()), records: []
    ).get()
    #expect(full.customActivities.count == TrainingLog.maximumExercises)
    let restored = ActivityLog.make(customActivities: definitions, records: [])
      .map(\.customActivities.count)
    #expect(restored == .failure(.full))

    let log = try TrainingLog.make(exercises: [], sets: [], memos: [:], activities: full).get()
    let added = log.apply(.add(id: extra.id, name: "Extra activity", tracksDistance: false))
      .map(\.log.activities.customActivities.count)
    #expect(added == .failure(.full))
  }

  @Test func acceptsTheActivityRecordLimitAndRefusesOneMore() throws {
    let duration = try #require(ActivityDuration(minutes: 20))
    let records = (0..<UInt32(TrainingLog.maximumSets)).map { number in
      LoggedActivity(
        id: LoggedActivityID(uuid(number)), activityID: .walking, day: .earliest,
        duration: duration, distance: nil)
    }
    let extra = LoggedActivity(
      id: LoggedActivityID(uuid(UInt32(TrainingLog.maximumSets))), activityID: .walking,
      day: .earliest, duration: duration, distance: nil)
    let full = try ActivityLog.make(customActivities: [], records: records).get()
    #expect(full.records.count == TrainingLog.maximumSets)
    let restored = ActivityLog.make(customActivities: [], records: records + [extra])
      .map(\.records.count)
    #expect(restored == .failure(.full))

    let log = try TrainingLog.make(exercises: [], sets: [], memos: [:], activities: full).get()
    let logged = log.apply(.record(extra)).map(\.log.activities.records.count)
    #expect(logged == .failure(.full))
  }

  @Test func acceptsDecimalUnitInputsAndEnforcesTheirBounds() {
    #expect(WeightUnit.pounds.parse(" .5 ").map(\.hundredths) == .success(23))
    #expect(WeightUnit.pounds.parse("1,2").map(\.hundredths) == .success(54))
    #expect(WeightUnit.pounds.parse("12.34").map(\.hundredths) == .success(560))
    #expect(WeightUnit.pounds.parse("2204.6").map(\.hundredths) == .success(99_999))
    #expect(WeightUnit.pounds.parse("2204.61") == .failure(.outOfRange))
    #expect(WeightUnit.pounds.parse("2205") == .failure(.outOfRange))
    #expect(WeightUnit.pounds.parse(String(repeating: "9", count: 200)) == .failure(.outOfRange))
    #expect(WeightUnit.pounds.parse("1.234") == .failure(.tooPrecise))
    #expect(WeightUnit.pounds.parse(".") == .failure(.notANumber))

    #expect(DistanceUnit.kilometers.parse("1.25")?.meters == 1_250)
    #expect(DistanceUnit.kilometers.parse("1000")?.meters == ActivityDistance.maximumMeters)
    #expect(DistanceUnit.kilometers.parse("1000.001") == nil)
    #expect(DistanceUnit.kilometers.parse(String(repeating: "9", count: 200)) == nil)
    #expect(DistanceUnit.miles.parse(".5")?.meters == 805)
    #expect(DistanceUnit.miles.parse("1.0001") == nil)
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

  @Test func quotesAndExportsAnActivityNameWithAFormulaPrefixAsText() throws {
    let day = try #require(LocalDay(iso: "2026-11-19"))
    let duration = try #require(ActivityDuration(minutes: 20))
    let id = TimedActivityID(UUID())
    let named = try TrainingLog.empty.apply(
      .add(id: id, name: "=steady, \"short\"", tracksDistance: false)
    ).get().log
    let record = LoggedActivity(
      id: LoggedActivityID(UUID()), activityID: id, day: day, duration: duration, distance: nil)
    let logged = try named.apply(.record(record)).get().log
    let csv = CSVExport.writeActivities(
      logged,
      labels: ActivityCSVLabels(
        day: " \t+Date", activity: "Activity", minutes: "min", meters: "m", walking: "Walking"))
    #expect(
      String(decoding: csv.dropFirst(3), as: UTF8.self)
        == "' \t+Date,Activity,min,m\r\n2026-11-19,\"'=steady, \"\"short\"\"\",20,\r\n")
  }
}
