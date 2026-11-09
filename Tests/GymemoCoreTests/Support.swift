import Foundation
import GymemoCore
import Testing

func uuid(_ number: UInt32) -> UUID {
  let bytes = withUnsafeBytes(of: number.bigEndian, Array.init)
  return UUID(
    uuid: (
      0x67, 0x79, 0x6D, 0x65, 0x6D, 0x6F, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00,
      bytes[0], bytes[1], bytes[2], bytes[3]
    ))
}

func exerciseID(_ number: UInt32) -> ExerciseID { ExerciseID(uuid(number)) }

func setID(_ number: UInt32) -> SetID { SetID(uuid(number)) }

func day(_ iso: String) throws -> LocalDay { try #require(LocalDay(iso: iso)) }

func kilograms(_ text: String) throws -> Weight { try Weight.parse(text).get() }

func reps(_ count: Int) throws -> Reps { try #require(Reps(count)) }

/// SplitMix64, so a seed names one reproducible sequence.
struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}

extension TrainingLog {
  /// The log after every command, or the first refusal as a thrown error.
  func applying(_ commands: Command...) throws -> TrainingLog {
    try commands.reduce(self) { log, command in try log.apply(command).get().log }
  }
}

/// The rows that an adapter keeps, changed only through the changes that a command returns.
struct RowModel: Equatable {
  var exercises: [Exercise] = []
  var sets: [LoggedSet] = []
  var memos: [LocalDay: Memo] = [:]

  init() {}

  init(_ log: TrainingLog) {
    exercises = log.exercises
    sets = log.sets
    memos = log.memos
  }

  mutating func store(_ changes: [Change]) {
    for change in changes {
      switch change {
      case .putExercise(let exercise):
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
          exercises[index] = exercise
        } else {
          exercises.append(exercise)
        }
      case .removeExercise(let id):
        exercises.removeAll { $0.id == id }
      case .putSet(let set):
        if let index = sets.firstIndex(where: { $0.id == set.id }) {
          sets[index] = set
        } else {
          sets.append(set)
        }
      case .removeSet(let id):
        sets.removeAll { $0.id == id }
      case .putMemo(let day, let memo):
        memos[day] = memo
      case .removeMemo(let day):
        memos[day] = nil
      case .replaceAll(let log):
        self = RowModel(log)
      }
    }
  }
}
