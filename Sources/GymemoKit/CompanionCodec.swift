import Foundation
import GymemoCore

public enum CompanionFileOperation: String, Equatable, Sendable {
  case read, write
}

public enum CompanionFailure: Error, Equatable, Sendable {
  case tooLarge
  case malformed
  case unsupportedVersion
  case duplicateIdentifier
  case queueFull
  case file(operation: CompanionFileOperation, code: Int)
}

/// The versioned, bounded wire format for paired-device messages.
public enum CompanionCodec {
  public static let maximumBytes = 60_000

  private struct SetRecord: Codable {
    let id: UUID
    let exercise: UUID
    let day: String
    let hundredths: Int
    let reps: Int

    init(_ set: LoggedSet) {
      id = set.id.uuid
      exercise = set.exerciseID.uuid
      day = set.day.iso
      hundredths = set.weight.hundredths
      reps = set.reps.count
    }

    func validated() throws(CompanionFailure) -> LoggedSet {
      guard let day = LocalDay(iso: day), let weight = Weight(hundredths: hundredths),
        let reps = Reps(reps)
      else { throw .malformed }
      return LoggedSet(
        id: SetID(id), exerciseID: ExerciseID(exercise), day: day, weight: weight, reps: reps)
    }
  }

  private struct ExerciseRecord: Codable {
    let id: UUID
    let name: String
    let bodyPart: String
    let hundredths: Int?
    let reps: Int?

    init(_ item: CompanionExercise) {
      id = item.id.uuid
      name = item.exercise.name.text
      bodyPart = item.exercise.bodyPart.rawValue
      hundredths = item.suggestion?.weight.hundredths
      reps = item.suggestion?.reps.count
    }

    func validated() throws(CompanionFailure) -> CompanionExercise {
      guard case .success(let name) = ExerciseName.parse(name),
        let bodyPart = BodyPart(rawValue: bodyPart)
      else { throw .malformed }
      let suggestion: SetEntry?
      switch (hundredths, reps) {
      case (nil, nil): suggestion = nil
      case (.some(let load), .some(let count)):
        guard let weight = Weight(hundredths: load), let repetitions = Reps(count) else {
          throw .malformed
        }
        suggestion = SetEntry(weight: weight, reps: repetitions)
      default: throw .malformed
      }
      return CompanionExercise(
        exercise: Exercise(id: ExerciseID(id), name: name, bodyPart: bodyPart),
        suggestion: suggestion)
    }
  }

  private enum Kind: String, Codable {
    case catalog, entry, receipt
  }

  private struct Envelope: Codable {
    let version: Int
    let kind: Kind
    var entry: SetRecord?
    var outcome: String?
    var exercises: [ExerciseRecord]?
  }

  public static func encode(_ message: CompanionMessage) throws(CompanionFailure) -> Data {
    let envelope: Envelope
    switch message {
    case .entry(let set):
      envelope = Envelope(version: 1, kind: .entry, entry: SetRecord(set))
    case .receipt(let receipt):
      envelope = Envelope(
        version: 1, kind: .receipt, entry: SetRecord(receipt.set), outcome: receipt.outcome.rawValue
      )
    case .catalog(let catalog):
      envelope = Envelope(
        version: 1, kind: .catalog, exercises: catalog.exercises.map(ExerciseRecord.init))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(envelope) else { throw .malformed }
    guard data.count <= maximumBytes else { throw .tooLarge }
    return data
  }

  public static func decode(_ data: Data) throws(CompanionFailure) -> CompanionMessage {
    guard data.count <= maximumBytes else { throw .tooLarge }
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
      throw .malformed
    }
    guard envelope.version == 1 else { throw .unsupportedVersion }
    switch envelope.kind {
    case .entry:
      guard let entry = envelope.entry, envelope.outcome == nil, envelope.exercises == nil else {
        throw .malformed
      }
      return .entry(try entry.validated())
    case .receipt:
      guard let entry = envelope.entry,
        let outcome = envelope.outcome.flatMap(CompanionOutcome.init(rawValue:)),
        envelope.exercises == nil
      else { throw .malformed }
      return .receipt(CompanionReceipt(set: try entry.validated(), outcome: outcome))
    case .catalog:
      guard let records = envelope.exercises, records.count <= CompanionCatalog.maximumExercises,
        envelope.entry == nil, envelope.outcome == nil
      else { throw .malformed }
      let exercises = try records.map { item throws(CompanionFailure) in try item.validated() }
      guard let catalog = CompanionCatalog(exercises: exercises) else { throw .malformed }
      return .catalog(catalog)
    }
  }
}
