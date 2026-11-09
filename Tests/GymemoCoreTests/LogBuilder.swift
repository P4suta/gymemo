import GymemoCore
import Testing

/// Builds a log from short literal rows, numbering the sets in logging order from 1.
struct LogBuilder {
  private(set) var log = TrainingLog.empty
  private var nextSet: UInt32 = 1

  mutating func exercise(_ number: UInt32, _ name: String, _ part: BodyPart = .other) throws {
    log = try log.applying(.addExercise(id: exerciseID(number), name: name, bodyPart: part))
  }

  @discardableResult
  mutating func set(
    _ exercise: UInt32, _ iso: String, _ weight: String, _ count: Int
  ) throws -> SetID {
    let id = setID(nextSet)
    nextSet += 1
    log = try log.applying(
      .logSet(
        id: id, exerciseID: exerciseID(exercise), day: day(iso), weight: kilograms(weight),
        reps: reps(count)))
    return id
  }

  mutating func apply(_ command: Command) throws {
    log = try log.applying(command)
  }
}
