public enum IntegrityRefusal: Error, Equatable, Sendable {
  case duplicateExerciseID
  case duplicateExerciseName
  case duplicateSetID
  case unknownExercise
  case tooManyExercises
  case tooManySets
}

/// Every exercise, set, and memo of one lifter.
/// Exercise identifiers, exercise names, and set identifiers are unique, and every set names a stored exercise.
/// Exercises and sets keep the order in which the lifter added them.
public struct TrainingLog: Equatable, Sendable {
  public static let maximumExercises = 1_000
  public static let maximumSets = 1_000_000
  public static let empty = TrainingLog(unchecked: [], sets: [], memos: [:])

  public let exercises: [Exercise]
  public let sets: [LoggedSet]
  public let memos: [LocalDay: Memo]

  private let exercisePositions: [ExerciseID: Int]
  private let setPositions: [SetID: Int]
  private let setPositionsByExercise: [ExerciseID: [Int]]
  private let setPositionsByDay: [LocalDay: [Int]]

  /// Builds a log from rows that already satisfy the invariants.
  init(unchecked exercises: [Exercise], sets: [LoggedSet], memos: [LocalDay: Memo]) {
    self.exercises = exercises
    self.sets = sets
    self.memos = memos
    var exercisePositions: [ExerciseID: Int] = [:]
    for (position, exercise) in exercises.enumerated() {
      exercisePositions[exercise.id] = position
    }
    var setPositions: [SetID: Int] = [:]
    var byExercise: [ExerciseID: [Int]] = [:]
    var byDay: [LocalDay: [Int]] = [:]
    for (position, set) in sets.enumerated() {
      setPositions[set.id] = position
      byExercise[set.exerciseID, default: []].append(position)
      byDay[set.day, default: []].append(position)
    }
    self.exercisePositions = exercisePositions
    self.setPositions = setPositions
    setPositionsByExercise = byExercise
    setPositionsByDay = byDay
  }

  /// Builds a log from rows of unknown origin, such as a file or a database.
  public static func make(
    exercises: [Exercise], sets: [LoggedSet], memos: [LocalDay: Memo]
  ) -> Result<TrainingLog, IntegrityRefusal> {
    guard exercises.count <= maximumExercises else { return .failure(.tooManyExercises) }
    guard sets.count <= maximumSets else { return .failure(.tooManySets) }
    var exerciseIDs: Set<ExerciseID> = []
    var names: Set<ExerciseName> = []
    for exercise in exercises {
      guard exerciseIDs.insert(exercise.id).inserted else { return .failure(.duplicateExerciseID) }
      guard names.insert(exercise.name).inserted else { return .failure(.duplicateExerciseName) }
    }
    var setIDs: Set<SetID> = []
    for set in sets {
      guard setIDs.insert(set.id).inserted else { return .failure(.duplicateSetID) }
      guard exerciseIDs.contains(set.exerciseID) else { return .failure(.unknownExercise) }
    }
    return .success(TrainingLog(unchecked: exercises, sets: sets, memos: memos))
  }

  public func exercise(_ id: ExerciseID) -> Exercise? {
    exercisePositions[id].map { exercises[$0] }
  }

  public func set(_ id: SetID) -> LoggedSet? {
    setPositions[id].map { sets[$0] }
  }

  /// The sets of one exercise in logging order.
  public func sets(of exercise: ExerciseID) -> [LoggedSet] {
    (setPositionsByExercise[exercise] ?? []).map { sets[$0] }
  }

  /// The sets of one day in logging order.
  public func sets(on day: LocalDay) -> [LoggedSet] {
    (setPositionsByDay[day] ?? []).map { sets[$0] }
  }

  public func memo(on day: LocalDay) -> Memo? {
    memos[day]
  }

  /// The days that hold at least one set.
  public var trainingDays: Set<LocalDay> {
    Set(setPositionsByDay.keys)
  }

  func position(of exercise: ExerciseID) -> Int? {
    exercisePositions[exercise]
  }

  func position(of set: SetID) -> Int? {
    setPositions[set]
  }
}
