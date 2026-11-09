import Foundation

public struct SetID: Hashable, Sendable {
  public let uuid: UUID

  public init(_ uuid: UUID) {
    self.uuid = uuid
  }
}

/// One set of one exercise on one day.
public struct LoggedSet: Hashable, Identifiable, Sendable {
  public let id: SetID
  public let exerciseID: ExerciseID
  public let day: LocalDay
  public var weight: Weight
  public var reps: Reps

  public init(id: SetID, exerciseID: ExerciseID, day: LocalDay, weight: Weight, reps: Reps) {
    self.id = id
    self.exerciseID = exerciseID
    self.day = day
    self.weight = weight
    self.reps = reps
  }
}

public enum MemoRefusal: Error, Equatable, Sendable {
  case tooLong
  case controlCharacter
}

/// A day's free text, with 1 to 2000 characters and line breaks written as line feeds.
public struct Memo: Hashable, Sendable {
  public static let maximumLength = 2000

  public let text: String

  /// The first line cut to `limit` characters, with an ellipsis when the memo holds more.
  public func preview(limit: Int) -> String {
    let line = text.prefix { !$0.isNewline }
    let shown = line.prefix(max(limit, 0))
    return shown.count == text.count ? String(shown) : shown + "…"
  }

  /// Reads a memo, where a successful `nil` means that the text holds nothing to keep.
  public static func parse(_ text: String) -> Result<Memo?, MemoRefusal> {
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let trimmed = String(lines.trimmedWhitespace)
    guard !trimmed.isEmpty else { return .success(nil) }
    let refused = trimmed.unicodeScalars.contains { scalar in
      scalar.properties.generalCategory == .control && scalar != "\n" && scalar != "\t"
    }
    guard !refused else { return .failure(.controlCharacter) }
    guard trimmed.count <= maximumLength else { return .failure(.tooLong) }
    return .success(Memo(text: trimmed))
  }
}
