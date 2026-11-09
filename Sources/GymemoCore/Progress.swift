/// The best set of one exercise on one day.
public struct ProgressPoint: Equatable, Identifiable, Sendable {
  public let day: LocalDay
  public let best: LoggedSet
  public let score: Score

  public var id: LocalDay { day }
}

public struct ExerciseProgress: Equatable, Sendable {
  public let exercise: Exercise
  /// The estimated one-repetition load once any set has added weight, and repetitions before that.
  public let kind: ScoreKind
  /// One point for each day with a set of that kind, from oldest to newest.
  public let points: [ProgressPoint]
  /// The highest point, and the earliest one when several tie.
  public let best: ProgressPoint?
  /// The set with the most added weight, then the most repetitions, then the earliest day.
  public let heaviest: LoggedSet?
  /// Every day of the exercise from newest to oldest.
  public let sessions: [Session]

  public func points(since day: LocalDay?) -> [ProgressPoint] {
    guard let day else { return points }
    return points.filter { $0.day >= day }
  }
}

public struct ExerciseSummary: Equatable, Identifiable, Sendable {
  public let exercise: Exercise
  public let lastDay: LocalDay
  public let best: ProgressPoint?

  public var id: ExerciseID { exercise.id }
}

/// The number of training days in the week that starts on `start`, a Monday.
public struct WeekCount: Equatable, Identifiable, Sendable {
  public let start: LocalDay
  public let days: Int

  public var id: LocalDay { start }
}

extension TrainingLog {
  public func progress(of id: ExerciseID) -> ExerciseProgress? {
    guard let exercise = exercise(id) else { return nil }
    let all = sets(of: id)
    let kind: ScoreKind = all.contains { !$0.weight.isBodyweight } ? .oneRepMax : .reps
    var bestOfDay: [LocalDay: ProgressPoint] = [:]
    var setsOfDay: [LocalDay: [LoggedSet]] = [:]
    for set in all {
      setsOfDay[set.day, default: []].append(set)
      let score = set.score
      guard score.kind == kind else { continue }
      if let known = bestOfDay[set.day], !score.beats(known.score) { continue }
      bestOfDay[set.day] = ProgressPoint(day: set.day, best: set, score: score)
    }
    let points = bestOfDay.values.sorted { $0.day < $1.day }
    var best: ProgressPoint?
    for point in points where best.map({ point.score.beats($0.score) }) ?? true {
      best = point
    }
    let days = setsOfDay.keys.sorted()
    var heaviest: LoggedSet?
    for set in days.flatMap({ setsOfDay[$0] ?? [] }) where !set.weight.isBodyweight {
      if let known = heaviest, (set.weight, set.reps) <= (known.weight, known.reps) { continue }
      heaviest = set
    }
    return ExerciseProgress(
      exercise: exercise, kind: kind, points: points, best: best, heaviest: heaviest,
      sessions: days.reversed().map { Session(day: $0, sets: setsOfDay[$0] ?? []) })
  }

  /// The exercises that have a set, from the most recently trained.
  public var exerciseSummaries: [ExerciseSummary] {
    exercisesByLatestUse.map { entry in
      ExerciseSummary(
        exercise: entry.exercise, lastDay: entry.day, best: progress(of: entry.exercise.id)?.best)
    }
  }

  /// The training days of each of the last `weeks` weeks, ending with the week of `today`.
  public func weeklyTrainingDays(through today: LocalDay, weeks: Int) -> [WeekCount] {
    var counts: [LocalDay: Int] = [:]
    for day in trainingDays {
      counts[day.weekStart, default: 0] += 1
    }
    var result: [WeekCount] = []
    var start: LocalDay? = today.weekStart
    while let current = start, result.count < weeks {
      result.append(WeekCount(start: current, days: counts[current] ?? 0))
      start = current.adding(days: -7)
    }
    return result.reversed()
  }
}
