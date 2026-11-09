public enum WeightRefusal: Error, Equatable, Sendable {
  case empty
  case notANumber
  case tooPrecise
  case outOfRange
}

/// A load in hundredths of a kilogram, from 0 kg to 999.99 kg.
/// Zero means the body alone, with no added load.
public struct Weight: Hashable, Comparable, Sendable {
  public static let maximumHundredths = 99_999
  public static let bodyweight = Weight(unchecked: 0)

  public let hundredths: Int

  public init?(hundredths: Int) {
    guard (0...Self.maximumHundredths).contains(hundredths) else { return nil }
    self.hundredths = hundredths
  }

  private init(unchecked hundredths: Int) {
    self.hundredths = hundredths
  }

  public var isBodyweight: Bool { hundredths == 0 }

  /// The shortest decimal text in kilograms, such as `62.5`.
  public var text: String {
    let whole = hundredths / 100
    let fraction = hundredths % 100
    if fraction == 0 { return "\(whole)" }
    if fraction % 10 == 0 { return "\(whole).\(fraction / 10)" }
    return "\(whole).\(fraction / 10)\(fraction % 10)"
  }

  public static func < (left: Weight, right: Weight) -> Bool {
    left.hundredths < right.hundredths
  }

  /// Reads kilograms written with ASCII digits and at most two decimals after `.` or `,`.
  public static func parse(_ text: String) -> Result<Weight, WeightRefusal> {
    let trimmed = text.trimmedWhitespace
    guard !trimmed.isEmpty else { return .failure(.empty) }
    let parts = trimmed.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
    guard parts.count <= 2, let whole = parts.first else { return .failure(.notANumber) }
    let fraction = parts.count == 2 ? parts[1] : ""
    guard !(whole.isEmpty && fraction.isEmpty),
      let kilograms = whole.asciiNumber(limit: maximumHundredths),
      let decimals = fraction.asciiNumber(limit: maximumHundredths)
    else { return .failure(.notANumber) }
    guard fraction.utf8.count <= 2 else { return .failure(.tooPrecise) }
    let scaled = fraction.utf8.count == 1 ? decimals * 10 : decimals
    guard let weight = Weight(hundredths: kilograms * 100 + scaled) else {
      return .failure(.outOfRange)
    }
    return .success(weight)
  }
}

public enum RepsRefusal: Error, Equatable, Sendable {
  case empty
  case notANumber
  case outOfRange
}

/// The number of repetitions in one set, from 1 to 999.
public struct Reps: Hashable, Comparable, Sendable {
  public static let maximumCount = 999
  public static let one = Reps(unchecked: 1)

  public let count: Int

  public init?(_ count: Int) {
    guard (1...Self.maximumCount).contains(count) else { return nil }
    self.count = count
  }

  private init(unchecked count: Int) {
    self.count = count
  }

  public static func < (left: Reps, right: Reps) -> Bool {
    left.count < right.count
  }

  /// Reads a whole number written with ASCII digits.
  public static func parse(_ text: String) -> Result<Reps, RepsRefusal> {
    let trimmed = text.trimmedWhitespace
    guard !trimmed.isEmpty else { return .failure(.empty) }
    guard let count = trimmed.asciiNumber(limit: maximumCount) else {
      return .failure(.notANumber)
    }
    guard let reps = Reps(count) else { return .failure(.outOfRange) }
    return .success(reps)
  }
}

extension Weight {
  /// One step of a weight stepper, 2.5 kg.
  public static let stepHundredths = 250

  /// The weight that a stepper reaches from the text of a weight field, held between bodyweight and the heaviest weight.
  /// An empty field counts as bodyweight, and a text that isn't a weight gives nil.
  public static func stepped(from text: String, by steps: Int) -> Weight? {
    let start: Weight
    switch parse(text) {
    case .success(let weight): start = weight
    case .failure(.empty): start = .bodyweight
    case .failure: return nil
    }
    // No more steps than the range holds hundredths count, so the sum stays far from overflow.
    let counted = min(max(steps, -maximumHundredths), maximumHundredths)
    let moved = start.hundredths + counted * stepHundredths
    return Weight(unchecked: min(max(moved, 0), maximumHundredths))
  }
}

extension Reps {
  /// The repetitions that a stepper reaches from the text of a repetitions field, held between one and the largest count.
  /// An empty field steps up to one, and a text that isn't a count gives nil.
  public static func stepped(from text: String, by steps: Int) -> Reps? {
    let start: Int
    switch parse(text) {
    case .success(let reps): start = reps.count
    case .failure(.empty):
      guard steps > 0 else { return nil }
      start = 0
    case .failure: return nil
    }
    // No more steps than the range holds counts, so the sum stays far from overflow.
    let counted = min(max(steps, -maximumCount), maximumCount)
    return Reps(unchecked: min(max(start + counted, 1), maximumCount))
  }
}
