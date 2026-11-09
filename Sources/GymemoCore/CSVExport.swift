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

/// One row for each set, for a spreadsheet.
/// The file follows RFC 4180 and starts with a byte order mark, which lets Excel read it as UTF-8.
public enum CSVExport {
  public static func write(_ log: TrainingLog, labels: CSVLabels) -> Data {
    var lines = [
      [labels.day, labels.exercise, labels.bodyPart, labels.set, labels.weight, labels.reps]
    ]
    for day in log.trainingDays.sorted() {
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
    let text = lines.map { $0.map(field).joined(separator: ",") + "\r\n" }.joined()
    return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
  }

  private static func field(_ text: String) -> String {
    guard text.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
