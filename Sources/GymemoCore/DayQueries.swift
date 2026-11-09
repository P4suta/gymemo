/// One exercise on one day with its sets in logging order.
public struct DaySection: Equatable, Sendable {
  public let exercise: Exercise
  public let sets: [LoggedSet]
}

/// The sets of one exercise on one day in logging order.
public struct Session: Equatable, Identifiable, Sendable {
  public let day: LocalDay
  public let sets: [LoggedSet]

  public var id: LocalDay { day }
}

public enum SetEntryRefusal: Error, Equatable, Sendable {
  case weight(WeightRefusal)
  case reps(RepsRefusal)
}

/// The weight and repetitions of a set that the lifter is about to log.
public struct SetEntry: Equatable, Sendable {
  public let weight: Weight
  public let reps: Reps

  public init(weight: Weight, reps: Reps) {
    self.weight = weight
    self.reps = reps
  }

  /// Reads the two inputs of a set, where an empty weight means the body alone.
  public static func parse(weight: String, reps: String) -> Result<SetEntry, SetEntryRefusal> {
    let load: Result<Weight, WeightRefusal> =
      switch Weight.parse(weight) {
      case .failure(.empty): .success(.bodyweight)
      case let other: other
      }
    return load.mapError(SetEntryRefusal.weight).flatMap { weight in
      Reps.parse(reps).mapError(SetEntryRefusal.reps).map { SetEntry(weight: weight, reps: $0) }
    }
  }
}

public struct DaySummary: Equatable, Identifiable, Sendable {
  public let day: LocalDay
  public let exerciseNames: [ExerciseName]
  public let setCount: Int
  public let memo: Memo?

  public var id: LocalDay { day }
}

/// The recorded days of one calendar month, from newest to oldest.
public struct HistoryMonth: Equatable, Identifiable, Sendable {
  public let days: [DaySummary]

  /// The first day of the month, or the earliest supported day for a month without days.
  public var start: LocalDay {
    days.first.flatMap { LocalDay(year: $0.day.year, month: $0.day.month, day: 1) } ?? .earliest
  }

  public var id: LocalDay { start }
}

public struct ExerciseGroup: Equatable, Identifiable, Sendable {
  public let bodyPart: BodyPart
  public let exercises: [Exercise]

  public var id: BodyPart { bodyPart }
}

extension TrainingLog {
  /// The exercises of `day` in the order of their first sets.
  public func sections(on day: LocalDay) -> [DaySection] {
    var order: [ExerciseID] = []
    var grouped: [ExerciseID: [LoggedSet]] = [:]
    for set in sets(on: day) {
      if grouped[set.exerciseID] == nil { order.append(set.exerciseID) }
      grouped[set.exerciseID, default: []].append(set)
    }
    return order.compactMap { id in
      exercise(id).map { DaySection(exercise: $0, sets: grouped[id] ?? []) }
    }
  }

  /// The latest day before `day` on which the lifter logged the exercise.
  public func previousSession(of exercise: ExerciseID, before day: LocalDay) -> Session? {
    let earlier = sets(of: exercise).filter { $0.day < day }
    guard let latest = earlier.map(\.day).max() else { return nil }
    return Session(day: latest, sets: earlier.filter { $0.day == latest })
  }

  /// The day's last set of the exercise, or else the first set of its previous session.
  public func suggestedEntry(for exercise: ExerciseID, on day: LocalDay) -> SetEntry? {
    let source =
      sets(of: exercise).last { $0.day == day }
      ?? previousSession(of: exercise, before: day)?.sets.first
    return source.map { SetEntry(weight: $0.weight, reps: $0.reps) }
  }

  /// Every day that holds a set or a memo, from newest to oldest.
  public var history: [DaySummary] {
    trainingDays.union(memos.keys).sorted(by: >).map { day in
      let sections = sections(on: day)
      return DaySummary(
        day: day, exerciseNames: sections.map(\.exercise.name),
        setCount: sections.reduce(0) { $0 + $1.sets.count }, memo: memos[day])
    }
  }

  /// The history grouped by calendar month, from the newest month to the oldest.
  public var historyByMonth: [HistoryMonth] {
    var months: [HistoryMonth] = []
    var days: [DaySummary] = []
    for summary in history {
      if let first = days.first,
        (first.day.year, first.day.month) != (summary.day.year, summary.day.month)
      {
        months.append(HistoryMonth(days: days))
        days = []
      }
      days.append(summary)
    }
    if !days.isEmpty { months.append(HistoryMonth(days: days)) }
    return months
  }

  /// The latest day and logging position of each exercise that has a set.
  var latestUse: [ExerciseID: (day: LocalDay, position: Int)] {
    var latest: [ExerciseID: (day: LocalDay, position: Int)] = [:]
    for (position, set) in sets.enumerated() {
      if let known = latest[set.exerciseID], known.day > set.day { continue }
      latest[set.exerciseID] = (set.day, position)
    }
    return latest
  }

  /// The exercises that have a set, from the most recently trained.
  var exercisesByLatestUse: [(exercise: Exercise, day: LocalDay)] {
    latestUse.sorted { left, right in
      (left.value.day, left.value.position) > (right.value.day, right.value.position)
    }
    .compactMap { entry in exercise(entry.key).map { ($0, entry.value.day) } }
  }

  /// The selectable exercises that the lifter trained most recently.
  public func recentExercises(limit: Int) -> [Exercise] {
    Array(exercisesByLatestUse.map(\.exercise).filter { !$0.isArchived }.prefix(max(limit, 0)))
  }

  /// The exercises that the lifter can pick for a new set, grouped by body part.
  public var selectableExercises: [ExerciseGroup] {
    groups(of: exercises.filter { !$0.isArchived })
  }

  /// Every exercise, grouped by body part.
  public var exercisesByBodyPart: [ExerciseGroup] {
    groups(of: exercises)
  }

  private func groups(of exercises: [Exercise]) -> [ExerciseGroup] {
    BodyPart.allCases.compactMap { part in
      let members = exercises.filter { $0.bodyPart == part }
      return members.isEmpty ? nil : ExerciseGroup(bodyPart: part, exercises: members)
    }
  }
}
