/// One thing the lifter asks the log to do.
/// The caller supplies new identifiers, so applying a command needs no randomness.
public enum Command: Equatable, Sendable {
  case addExercise(id: ExerciseID, name: String, bodyPart: BodyPart)
  case editExercise(id: ExerciseID, name: String, bodyPart: BodyPart)
  case setExerciseArchived(id: ExerciseID, isArchived: Bool)
  case deleteExercise(id: ExerciseID)
  case logSet(id: SetID, exerciseID: ExerciseID, day: LocalDay, weight: Weight, reps: Reps)
  case editSet(id: SetID, weight: Weight, reps: Reps)
  case deleteSet(id: SetID)
  case writeMemo(day: LocalDay, text: String)
  case replaceAll(TrainingLog)
}

/// One stored row to write or remove.
/// A put replaces the row with the same identifier or appends a new row after the existing ones.
public enum Change: Equatable, Sendable {
  case putExercise(Exercise)
  case removeExercise(ExerciseID)
  case putSet(LoggedSet)
  case removeSet(SetID)
  case putMemo(LocalDay, Memo)
  case removeMemo(LocalDay)
  case replaceAll(TrainingLog)
}

public enum Refusal: Error, Equatable, Sendable {
  case exerciseName(ExerciseNameRefusal)
  case duplicateExerciseName
  case duplicateIdentifier
  case unknownExercise
  case exerciseHasSets
  case unknownSet
  case memo(MemoRefusal)
  case full
}

/// The log after a command, with the row changes that make a store match it.
public struct Transition: Equatable, Sendable {
  public let log: TrainingLog
  public let changes: [Change]
}

extension TrainingLog {
  public func apply(_ command: Command) -> Result<Transition, Refusal> {
    switch command {
    case .addExercise(let id, let name, let bodyPart):
      addExercise(id: id, name: name, bodyPart: bodyPart)
    case .editExercise(let id, let name, let bodyPart):
      ExerciseName.parse(name).mapError(Refusal.exerciseName).flatMap { name in
        replaceExercise(id) { exercise in
          exercise.name = name
          exercise.bodyPart = bodyPart
        }
      }
    case .setExerciseArchived(let id, let isArchived):
      replaceExercise(id) { $0.isArchived = isArchived }
    case .deleteExercise(let id):
      deleteExercise(id)
    case .logSet(let id, let exerciseID, let day, let weight, let reps):
      logSet(LoggedSet(id: id, exerciseID: exerciseID, day: day, weight: weight, reps: reps))
    case .editSet(let id, let weight, let reps):
      editSet(id, weight: weight, reps: reps)
    case .deleteSet(let id):
      deleteSet(id)
    case .writeMemo(let day, let text):
      Memo.parse(text).mapError(Refusal.memo).map { writeMemo($0, on: day) }
    case .replaceAll(let log):
      .success(Transition(log: log, changes: [.replaceAll(log)]))
    }
  }

  private var unchanged: Transition { Transition(log: self, changes: []) }

  private func with(
    exercises: [Exercise]? = nil, sets: [LoggedSet]? = nil, memos: [LocalDay: Memo]? = nil,
    change: Change
  ) -> Transition {
    let log = TrainingLog(
      unchecked: exercises ?? self.exercises, sets: sets ?? self.sets, memos: memos ?? self.memos)
    return Transition(log: log, changes: [change])
  }

  private func addExercise(
    id: ExerciseID, name: String, bodyPart: BodyPart
  ) -> Result<Transition, Refusal> {
    ExerciseName.parse(name).mapError(Refusal.exerciseName).flatMap { name in
      guard exercise(id) == nil else { return .failure(.duplicateIdentifier) }
      guard !exercises.contains(where: { $0.name == name }) else {
        return .failure(.duplicateExerciseName)
      }
      guard exercises.count < Self.maximumExercises else { return .failure(.full) }
      let added = Exercise(id: id, name: name, bodyPart: bodyPart)
      return .success(with(exercises: exercises + [added], change: .putExercise(added)))
    }
  }

  private func replaceExercise(
    _ id: ExerciseID, _ edit: (inout Exercise) -> Void
  ) -> Result<Transition, Refusal> {
    guard let position = position(of: id) else { return .failure(.unknownExercise) }
    var edited = exercises[position]
    edit(&edited)
    guard edited != exercises[position] else { return .success(unchanged) }
    guard !exercises.contains(where: { $0.id != id && $0.name == edited.name }) else {
      return .failure(.duplicateExerciseName)
    }
    var replaced = exercises
    replaced[position] = edited
    return .success(with(exercises: replaced, change: .putExercise(edited)))
  }

  private func deleteExercise(_ id: ExerciseID) -> Result<Transition, Refusal> {
    guard let position = position(of: id) else { return .failure(.unknownExercise) }
    guard sets(of: id).isEmpty else { return .failure(.exerciseHasSets) }
    var remaining = exercises
    remaining.remove(at: position)
    return .success(with(exercises: remaining, change: .removeExercise(id)))
  }

  private func logSet(_ set: LoggedSet) -> Result<Transition, Refusal> {
    guard exercise(set.exerciseID) != nil else { return .failure(.unknownExercise) }
    guard self.set(set.id) == nil else { return .failure(.duplicateIdentifier) }
    guard sets.count < Self.maximumSets else { return .failure(.full) }
    return .success(with(sets: sets + [set], change: .putSet(set)))
  }

  private func editSet(_ id: SetID, weight: Weight, reps: Reps) -> Result<Transition, Refusal> {
    guard let position = position(of: id) else { return .failure(.unknownSet) }
    var edited = sets[position]
    edited.weight = weight
    edited.reps = reps
    guard edited != sets[position] else { return .success(unchanged) }
    var replaced = sets
    replaced[position] = edited
    return .success(with(sets: replaced, change: .putSet(edited)))
  }

  private func deleteSet(_ id: SetID) -> Result<Transition, Refusal> {
    guard let position = position(of: id) else { return .failure(.unknownSet) }
    var remaining = sets
    remaining.remove(at: position)
    return .success(with(sets: remaining, change: .removeSet(id)))
  }

  private func writeMemo(_ memo: Memo?, on day: LocalDay) -> Transition {
    guard memo != memos[day] else { return unchanged }
    var written = memos
    written[day] = memo
    return with(memos: written, change: memo.map { .putMemo(day, $0) } ?? .removeMemo(day))
  }
}
