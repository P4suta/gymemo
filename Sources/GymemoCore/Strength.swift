/// An estimate of the heaviest load that the lifter could move once.
/// `docs/design.md` records the formula's source and its limits.
public struct OneRepMax: Hashable, Comparable, Sendable {
  /// The estimate in units of 1/3000 kg, which keeps every comparison exact.
  private let units: Int

  /// Epley's estimate, the weight times (1 + repetitions / 30), and the weight itself for a single repetition.
  /// A set without added weight has no estimate.
  public static func estimate(weight: Weight, reps: Reps) -> OneRepMax? {
    guard !weight.isBodyweight else { return nil }
    return OneRepMax(units: weight.hundredths * (reps.count == 1 ? 30 : 30 + reps.count))
  }

  public var kilograms: Double { Double(units) / 3000 }

  /// Kilograms rounded half up to one decimal, such as `79.2`.
  public var text: String {
    let tenths = (units + 150) / 300
    return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
  }

  public static func < (left: OneRepMax, right: OneRepMax) -> Bool {
    left.units < right.units
  }
}

public enum ScoreKind: Hashable, Sendable {
  case oneRepMax
  case reps
}

/// What one set achieved: an estimated one-repetition load, or a repetition count without added weight.
public enum Score: Hashable, Sendable {
  case oneRepMax(OneRepMax)
  case reps(Reps)

  public var kind: ScoreKind {
    switch self {
    case .oneRepMax: .oneRepMax
    case .reps: .reps
    }
  }

  public var text: String {
    switch self {
    case .oneRepMax(let estimate): estimate.text
    case .reps(let reps): "\(reps.count)"
    }
  }

  /// The score as a number to plot, in kilograms or repetitions.
  public var value: Double {
    switch self {
    case .oneRepMax(let estimate): estimate.kilograms
    case .reps(let reps): Double(reps.count)
    }
  }

  /// Whether this score is higher than another score of the same kind.
  public func beats(_ other: Score) -> Bool {
    switch (self, other) {
    case (.oneRepMax(let mine), .oneRepMax(let theirs)): mine > theirs
    case (.reps(let mine), .reps(let theirs)): mine > theirs
    default: false
    }
  }
}

extension LoggedSet {
  public var score: Score {
    OneRepMax.estimate(weight: weight, reps: reps).map(Score.oneRepMax) ?? .reps(reps)
  }
}

extension TrainingLog {
  /// The sets of `day` that beat every earlier set of the same exercise and kind.
  /// A set counts only when an earlier day holds a set to beat, so a first session marks nothing.
  public func personalBests(on day: LocalDay) -> Set<SetID> {
    var marked: Set<SetID> = []
    for section in sections(on: day) {
      var best: [ScoreKind: Score] = [:]
      for set in sets(of: section.exercise.id) where set.day < day {
        let score = set.score
        if best[score.kind].map(score.beats) ?? true { best[score.kind] = score }
      }
      for set in section.sets {
        let score = set.score
        guard let earlier = best[score.kind], score.beats(earlier) else { continue }
        best[score.kind] = score
        marked.insert(set.id)
      }
    }
    return marked
  }
}
