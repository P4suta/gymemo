import GymemoCore
import Testing

func day(_ iso: String) throws -> LocalDay { try #require(LocalDay(iso: iso)) }

func kilograms(_ text: String) throws -> Weight { try Weight.parse(text).get() }

func reps(_ count: Int) throws -> Reps { try #require(Reps(count)) }

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
