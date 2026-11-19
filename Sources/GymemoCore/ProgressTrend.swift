public struct ProgressTrendPoint: Equatable, Identifiable, Sendable {
  public let day: LocalDay
  public let value: Double

  public var id: LocalDay { day }
}

public struct ProgressTrendSegment: Equatable, Identifiable, Sendable {
  public let id: LocalDay
  public let points: [ProgressTrendPoint]
}

extension ExerciseProgress {
  private static let minimumTrendDays = 5
  private static let maximumTrendDays = 9
  private static let maximumTrendGap = 42

  public func trend(since day: LocalDay?) -> [ProgressTrendSegment] {
    guard points.count >= Self.minimumTrendDays, let bounds = trendBounds else { return [] }
    let breaks = points.indices.dropFirst().filter { index in
      points[index].day.dayNumber - points[index - 1].day.dayNumber > Self.maximumTrendGap
    }
    var start = points.startIndex
    return (breaks + [points.endIndex]).compactMap { end in
      let group = points[start..<end]
      start = end
      return Self.trend(in: group, since: day, bounds: bounds)
    }
  }

  private var trendBounds: ClosedRange<Double>? {
    switch kind {
    case .reps:
      return 1...Double(Reps.maximumCount)
    case .oneRepMax:
      guard let weight = Weight(hundredths: Weight.maximumHundredths),
        let reps = Reps(Reps.maximumCount),
        let maximum = OneRepMax.estimate(weight: weight, reps: reps)
      else { return nil }
      return 0...maximum.kilograms
    }
  }

  private static func trend(
    in group: ArraySlice<ProgressPoint>, since day: LocalDay?, bounds: ClosedRange<Double>
  ) -> ProgressTrendSegment? {
    guard group.count >= minimumTrendDays, let firstDay = group.first?.day else { return nil }
    let visible = day.map { start in group.drop(while: { $0.day < start }) } ?? group
    guard visible.count >= 2 else { return nil }
    let count = min(group.count, maximumTrendDays)
    let points = visible.indices.map { index in
      let start = min(max(index - count / 2, group.startIndex), group.endIndex - count)
      let day = group[index].day
      let fitted = theilSenEstimate(at: day, from: group[start..<(start + count)])
      let value = min(max(fitted, bounds.lowerBound), bounds.upperBound)
      return ProgressTrendPoint(day: day, value: value)
    }
    return ProgressTrendSegment(id: firstDay, points: points)
  }

  private static func theilSenEstimate(
    at day: LocalDay, from window: ArraySlice<ProgressPoint>
  ) -> Double {
    let samples = window.map {
      (offset: Double($0.day.dayNumber - day.dayNumber), score: $0.score.value)
    }
    var slopes: [Double] = []
    for index in samples.indices {
      let start = samples[index]
      for end in samples.dropFirst(index + 1) {
        slopes.append((end.score - start.score) / (end.offset - start.offset))
      }
    }
    let slope = median(slopes)
    return median(samples.map { $0.score - slope * $0.offset })
  }

  private static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
  }
}
