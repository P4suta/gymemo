public enum CompanionOutcome: String, Equatable, Sendable {
  case saved
  case unknownExercise
  case identifierConflict
  case full
}

public struct CompanionReceipt: Equatable, Sendable {
  public let set: LoggedSet
  public let outcome: CompanionOutcome

  public init(set: LoggedSet, outcome: CompanionOutcome) {
    self.set = set
    self.outcome = outcome
  }
}

public struct CompanionExercise: Equatable, Identifiable, Sendable {
  public let exercise: Exercise
  public let suggestion: SetEntry?
  public var id: ExerciseID { exercise.id }

  public init(exercise: Exercise, suggestion: SetEntry?) {
    self.exercise = exercise
    self.suggestion = suggestion
  }
}

public struct CompanionCatalog: Equatable, Sendable {
  public static let maximumExercises = 40
  public let exercises: [CompanionExercise]

  public init(log: TrainingLog) {
    let recent = log.recentExercises(limit: Self.maximumExercises).filter { !$0.isArchived }
    let ids = Set(recent.map(\.id))
    let others = log.exercises.filter { !$0.isArchived && !ids.contains($0.id) }
    exercises = (recent + others).prefix(Self.maximumExercises).map { exercise in
      let last = log.sets(of: exercise.id).last
      return CompanionExercise(
        exercise: exercise, suggestion: last.map { SetEntry(weight: $0.weight, reps: $0.reps) })
    }
  }

  public init?(exercises: [CompanionExercise]) {
    guard exercises.count <= Self.maximumExercises,
      Set(exercises.map(\.id)).count == exercises.count,
      Set(exercises.map(\.exercise.name)).count == exercises.count,
      exercises.allSatisfy({ !$0.exercise.isArchived })
    else { return nil }
    self.exercises = exercises
  }
}

public enum CompanionMessage: Equatable, Sendable {
  case catalog(CompanionCatalog)
  case entry(LoggedSet)
  case receipt(CompanionReceipt)
}
