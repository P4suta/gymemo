import Foundation
import GymemoCore
import Testing

enum ActivityVectors {
  private static let names = ["Stretching", "Cycling"]

  static func render() throws -> String {
    let day = try #require(LocalDay(iso: "2026-11-19"))
    let duration = try #require(ActivityDuration(minutes: 20))
    let shorter = try #require(ActivityDuration(minutes: 10))
    let distance = try #require(ActivityDistance(meters: 1_500))
    let stretching = TimedActivityID(uuid(2))
    let cycling = TimedActivityID(uuid(3))
    let walk = LoggedActivity(
      id: LoggedActivityID(uuid(5)), activityID: .walking, day: day, duration: duration,
      distance: distance)
    let stretch = LoggedActivity(
      id: LoggedActivityID(uuid(6)), activityID: stretching, day: day, duration: shorter,
      distance: nil)
    var invalid = stretch
    invalid.distance = distance
    let commands: [ActivityCommand] = [
      .record(walk),
      .record(walk),
      .record(stretch),
      .add(id: stretching, name: names[0], tracksDistance: false),
      .add(id: cycling, name: names[0], tracksDistance: true),
      .add(id: cycling, name: names[1], tracksDistance: true),
      .record(invalid),
      .record(stretch),
      .edit(stretch.id, duration: shorter, distance: distance),
      .edit(walk.id, duration: duration, distance: distance),
      .edit(walk.id, duration: shorter, distance: nil),
      .delete(stretch.id),
      .delete(stretch.id),
    ]
    var log = TrainingLog.empty
    var steps: [String] = []
    for command in commands {
      switch log.apply(command) {
      case .success(let transition):
        log = transition.log
        steps.append("some \(list(transition.changes.map(change)))")
      case .failure:
        steps.append("none")
      }
    }
    let activities = list(log.activities.customActivities.map(activity))
    let records = list(log.activities.records.map(record))
    return """
      import Gymemo.Activities

      namespace Gymemo.Activities

      def sampleCommands : List Command := \(list(commands.map(command)))

      def sampleSteps : List (Option (List Change)) := \(list(steps))

      def finalLog : Log := ⟨\(activities), \(records)⟩

      example : run empty sampleCommands = (sampleSteps, finalLog) := by decide

      end Gymemo.Activities

      """
  }

  private static func list(_ entries: [String]) -> String {
    "[" + entries.joined(separator: ", ") + "]"
  }

  private static func uuid(_ number: UInt8) -> UUID {
    UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
  }

  private static func activity(_ value: TimedActivity) -> String {
    activity(id: value.id, name: value.name?.text ?? "", tracksDistance: value.tracksDistance)
  }

  private static func activity(id: TimedActivityID, name: String, tracksDistance: Bool) -> String {
    let index = names.firstIndex(of: name).map { $0 + 1 } ?? 0
    return "⟨\(id.uuid.uuid.15), \(index), \(tracksDistance)⟩"
  }

  private static func record(_ value: LoggedActivity) -> String {
    "⟨\(value.id.uuid.uuid.15), \(value.activityID.uuid.uuid.15), \(value.day.dayNumber), "
      + "\(value.duration.minutes), \(meters(value.distance))⟩"
  }

  private static func meters(_ distance: ActivityDistance?) -> String {
    distance.map { "(some \($0.meters))" } ?? "none"
  }

  private static func command(_ value: ActivityCommand) -> String {
    switch value {
    case .add(let id, let name, let tracksDistance):
      ".add \(activity(id: id, name: name, tracksDistance: tracksDistance))"
    case .record(let entry):
      ".record \(record(entry))"
    case .edit(let id, let duration, let distance):
      ".edit \(id.uuid.uuid.15) \(duration.minutes) \(meters(distance))"
    case .delete(let id):
      ".delete \(id.uuid.uuid.15)"
    }
  }

  private static func change(_ value: ActivityChange) -> String {
    switch value {
    case .putActivity(let entry): ".putActivity \(activity(entry))"
    case .putRecord(let entry): ".putRecord \(record(entry))"
    case .removeRecord(let id): ".removeRecord \(id.uuid.uuid.15)"
    }
  }
}
