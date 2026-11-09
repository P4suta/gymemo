import Foundation

public enum BackupRefusal: Error, Equatable, Sendable {
  case tooLarge
  case notABackup
  case unsupportedVersion(Int)
  case invalidExercise(index: Int)
  case invalidSet(index: Int)
  case invalidMemo(index: Int)
  case integrity(IntegrityRefusal)
}

/// The JSON document that carries a whole log between installations.
/// `formatVersion` numbers the document's shape, and `read` accepts only the number that `write` produces.
public enum Backup {
  public static let format = "gymemo-backup"
  public static let formatVersion = 1
  public static let maximumBytes = 64 * 1_048_576

  private struct Header: Decodable {
    let format: String
    let formatVersion: Int
  }

  private struct Body: Decodable {
    let exercises: [ExerciseRow]
    let sets: [SetRow]
    let memos: [MemoRow]
  }

  private struct ExerciseRow: Decodable {
    let id: String
    let name: String
    let bodyPart: String
    let archived: Bool
  }

  private struct SetRow: Decodable {
    let id: String
    let exercise: String
    let day: String
    let weightKg: String
    let reps: Int
  }

  private struct MemoRow: Decodable {
    let day: String
    let text: String
  }

  /// Writes one row on each line, in the log's own order, so equal logs give equal bytes.
  public static func write(_ log: TrainingLog) -> Data {
    let exercises = log.exercises.map { exercise in
      """
      {"id":\(quoted(exercise.id.uuid.uuidString)),"name":\(quoted(exercise.name.text)),\
      "bodyPart":\(quoted(exercise.bodyPart.rawValue)),"archived":\(exercise.isArchived)}
      """
    }
    let sets = log.sets.map { set in
      """
      {"id":\(quoted(set.id.uuid.uuidString)),"exercise":\(quoted(set.exerciseID.uuid.uuidString)),\
      "day":\(quoted(set.day.iso)),"weightKg":\(quoted(set.weight.text)),"reps":\(set.reps.count)}
      """
    }
    let memos = log.memos.sorted { $0.key < $1.key }.map { day, memo in
      "{\"day\":\(quoted(day.iso)),\"text\":\(quoted(memo.text))}"
    }
    let text = """
      {"format":\(quoted(format)),"formatVersion":\(formatVersion),
      "exercises":[\(rows(exercises))],
      "sets":[\(rows(sets))],
      "memos":[\(rows(memos))]}

      """
    return Data(text.utf8)
  }

  public static func read(_ data: Data) -> Result<TrainingLog, BackupRefusal> {
    guard data.count <= maximumBytes else { return .failure(.tooLarge) }
    let decoder = JSONDecoder()
    guard let header = try? decoder.decode(Header.self, from: data), header.format == format
    else { return .failure(.notABackup) }
    guard header.formatVersion == formatVersion else {
      return .failure(.unsupportedVersion(header.formatVersion))
    }
    guard let body = try? decoder.decode(Body.self, from: data) else {
      return .failure(.notABackup)
    }
    var exercises: [Exercise] = []
    for (index, row) in body.exercises.enumerated() {
      guard let uuid = UUID(uuidString: row.id), let bodyPart = BodyPart(rawValue: row.bodyPart),
        case .success(let name) = ExerciseName.parse(row.name)
      else { return .failure(.invalidExercise(index: index)) }
      exercises.append(
        Exercise(id: ExerciseID(uuid), name: name, bodyPart: bodyPart, isArchived: row.archived))
    }
    var sets: [LoggedSet] = []
    for (index, row) in body.sets.enumerated() {
      guard let uuid = UUID(uuidString: row.id), let exercise = UUID(uuidString: row.exercise),
        let day = LocalDay(iso: row.day), case .success(let weight) = Weight.parse(row.weightKg),
        let reps = Reps(row.reps)
      else { return .failure(.invalidSet(index: index)) }
      sets.append(
        LoggedSet(
          id: SetID(uuid), exerciseID: ExerciseID(exercise), day: day, weight: weight, reps: reps))
    }
    var memos: [LocalDay: Memo] = [:]
    for (index, row) in body.memos.enumerated() {
      guard let day = LocalDay(iso: row.day), memos[day] == nil,
        case .success(let memo?) = Memo.parse(row.text)
      else { return .failure(.invalidMemo(index: index)) }
      memos[day] = memo
    }
    return TrainingLog.make(exercises: exercises, sets: sets, memos: memos)
      .mapError(BackupRefusal.integrity)
  }

  private static func rows(_ rows: [String]) -> String {
    rows.isEmpty ? "" : "\n" + rows.joined(separator: ",\n") + "\n"
  }

  /// A JSON string literal, which escapes the quote, the backslash, and every control character.
  private static func quoted(_ text: String) -> String {
    var literal = String.UnicodeScalarView()
    literal.append("\"")
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": literal.append(contentsOf: "\\\"".unicodeScalars)
      case "\\": literal.append(contentsOf: "\\\\".unicodeScalars)
      case "\n": literal.append(contentsOf: "\\n".unicodeScalars)
      case "\t": literal.append(contentsOf: "\\t".unicodeScalars)
      case _ where scalar.value < 0x20:
        let digits = String(scalar.value, radix: 16)
        literal.append(
          contentsOf: ("\\u" + (digits.count == 1 ? "000" : "00") + digits).unicodeScalars)
      default: literal.append(scalar)
      }
    }
    literal.append("\"")
    return String(literal)
  }
}
