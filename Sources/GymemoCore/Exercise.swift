import Foundation

public struct ExerciseID: Hashable, Sendable {
  public let uuid: UUID

  public init(_ uuid: UUID) {
    self.uuid = uuid
  }
}

/// The part of the body that an exercise trains, stored by its raw value.
public enum BodyPart: String, CaseIterable, Sendable {
  case chest, back, legs, shoulders, arms, abdominals, other
}

public enum ExerciseNameRefusal: Error, Equatable, Sendable {
  case empty
  case tooLong
  case controlCharacter
}

/// An exercise's name on one line, in Unicode Normalization Form C, with 1 to 40 characters.
public struct ExerciseName: Hashable, Sendable {
  public static let maximumLength = 40

  public let text: String

  public static func parse(_ text: String) -> Result<ExerciseName, ExerciseNameRefusal> {
    let trimmed = String(text.trimmedWhitespace).precomposedStringWithCanonicalMapping
    guard !trimmed.isEmpty else { return .failure(.empty) }
    let controls: Set<Unicode.GeneralCategory> = [.control, .lineSeparator, .paragraphSeparator]
    guard
      !trimmed.unicodeScalars.contains(where: { controls.contains($0.properties.generalCategory) })
    else { return .failure(.controlCharacter) }
    guard trimmed.count <= maximumLength else { return .failure(.tooLong) }
    return .success(ExerciseName(text: trimmed))
  }
}

public struct Exercise: Hashable, Identifiable, Sendable {
  public let id: ExerciseID
  public var name: ExerciseName
  public var bodyPart: BodyPart
  public var isArchived: Bool

  public init(id: ExerciseID, name: ExerciseName, bodyPart: BodyPart, isArchived: Bool = false) {
    self.id = id
    self.name = name
    self.bodyPart = bodyPart
    self.isArchived = isArchived
  }
}
