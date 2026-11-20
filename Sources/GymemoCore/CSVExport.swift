import Foundation

/// The words of the app's language that a CSV file shows.
public struct CSVLabels: Sendable {
  public let day: String
  public let exercise: String
  public let bodyPart: String
  public let set: String
  public let weight: String
  public let reps: String
  public let bodyParts: [BodyPart: String]

  public init(
    day: String, exercise: String, bodyPart: String, set: String, weight: String, reps: String,
    bodyParts: [BodyPart: String]
  ) {
    self.day = day
    self.exercise = exercise
    self.bodyPart = bodyPart
    self.set = set
    self.weight = weight
    self.reps = reps
    self.bodyParts = bodyParts
  }
}

public struct ActivityCSVLabels: Sendable {
  public let day: String
  public let activity: String
  public let minutes: String
  public let meters: String
  public let walking: String

  public init(day: String, activity: String, minutes: String, meters: String, walking: String) {
    self.day = day
    self.activity = activity
    self.minutes = minutes
    self.meters = meters
    self.walking = walking
  }
}

/// One row for each set, for a spreadsheet.
/// The file follows RFC 4180 and starts with a byte order mark, which lets Excel read it as UTF-8.
public enum CSVExport {
  public static func write(_ log: TrainingLog, labels: CSVLabels) -> Data {
    var lines = [
      [labels.day, labels.exercise, labels.bodyPart, labels.set, labels.weight, labels.reps]
    ]
    for day in log.strengthDays.sorted() {
      for section in log.sections(on: day) {
        let part = labels.bodyParts[section.exercise.bodyPart] ?? section.exercise.bodyPart.rawValue
        for (index, set) in section.sets.enumerated() {
          lines.append([
            day.iso, section.exercise.name.text, part, "\(index + 1)", set.weight.text,
            "\(set.reps.count)",
          ])
        }
      }
    }
    return data(lines)
  }

  public static func writeActivities(_ log: TrainingLog, labels: ActivityCSVLabels) -> Data {
    var lines = [[labels.day, labels.activity, labels.minutes, labels.meters]]
    for day in log.activities.days.sorted() {
      for record in log.activities.records(on: day) {
        let name = log.activities.activity(record.activityID)?.name?.text ?? labels.walking
        lines.append([
          day.iso, name, String(record.duration.minutes),
          record.distance.map { String($0.meters) } ?? "",
        ])
      }
    }
    return data(lines)
  }

  private static func data(_ lines: [[String]]) -> Data {
    let text = lines.map { $0.map(field).joined(separator: ",") + "\r\n" }.joined()
    return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
  }

  private static func field(_ text: String) -> String {
    let leading = text.unicodeScalars.first { !$0.properties.isWhitespace }
    let startsFormula = leading.map { "=+-@＝＋－＠".unicodeScalars.contains($0) } ?? false
    let value = startsFormula ? "'" + text : text
    guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
    return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
