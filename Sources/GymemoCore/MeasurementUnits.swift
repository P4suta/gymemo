public enum WeightUnit: String, CaseIterable, Sendable {
  case kilograms = "kg"
  case pounds = "lb"

  // NIST SP 811 gives 1 lb as exactly 0.45359237 kg.
  private static let poundNumerator: Int64 = 45_359_237
  private static let poundDenominator: Int64 = 100_000_000

  public func hundredths(for weight: Weight) -> Int {
    switch self {
    case .kilograms: return weight.hundredths
    case .pounds:
      let pounds = Int(
        roundedQuotient(
          Int64(weight.hundredths) * Self.poundDenominator, Self.poundNumerator))
      let tenth = ((pounds + 5) / 10) * 10
      return Self.kilogramHundredths(pounds: tenth) == weight.hundredths ? tenth : pounds
    }
  }

  public func value(kilograms: Double) -> Double {
    switch self {
    case .kilograms: kilograms
    case .pounds: kilograms * Double(Self.poundDenominator) / Double(Self.poundNumerator)
    }
  }

  public func parse(_ text: String) -> Result<Weight, WeightRefusal> {
    switch self {
    case .kilograms: Weight.parse(text)
    case .pounds:
      parseDecimal(text, places: 2, limit: hundredths(for: Self.maximumWeight)).flatMap {
        pounds in
        let kilograms = Self.kilogramHundredths(pounds: pounds)
        guard pounds == 0 || kilograms > 0, let weight = Weight(hundredths: kilograms) else {
          return .failure(.outOfRange)
        }
        return .success(weight)
      }
    }
  }

  public func stepped(from weight: Weight, by steps: Int) -> Weight {
    switch self {
    case .kilograms: return Weight.stepped(from: weight.text, by: steps) ?? weight
    case .pounds:
      let maximum = hundredths(for: Self.maximumWeight)
      let counted = min(max(steps, -maximum), maximum)
      let moved = min(max(hundredths(for: weight) + counted * 500, 0), maximum)
      return Weight(hundredths: Self.kilogramHundredths(pounds: moved)) ?? Self.maximumWeight
    }
  }

  private static var maximumWeight: Weight {
    Weight(hundredths: Weight.maximumHundredths) ?? .bodyweight
  }

  private static func kilogramHundredths(pounds: Int) -> Int {
    Int(roundedQuotient(Int64(pounds) * poundNumerator, poundDenominator))
  }
}

public enum DistanceUnit: String, CaseIterable, Sendable {
  case kilometers = "km"
  case miles = "mi"

  // NIST SP 811 gives 1 mi as exactly 1609.344 m.
  private static let mileMeters = 1_609.344
  private static let mileNumerator: Int64 = 1_609_344
  private static let mileDenominator: Int64 = 1_000_000

  public func parse(_ text: String) -> ActivityDistance? {
    guard
      case .success(let value) = parseDecimal(
        text, places: 3, limit: ActivityDistance.maximumMeters)
    else { return nil }
    switch self {
    case .kilometers: return ActivityDistance(meters: value)
    case .miles:
      let meters = roundedQuotient(Int64(value) * Self.mileNumerator, Self.mileDenominator)
      return ActivityDistance(meters: Int(meters))
    }
  }

  public func thousandths(for distance: ActivityDistance) -> Int {
    switch self {
    case .kilometers: distance.meters
    case .miles:
      Int(
        roundedQuotient(
          Int64(distance.meters) * Self.mileDenominator, Self.mileNumerator))
    }
  }

  public func value(meters: Double) -> Double {
    switch self {
    case .kilometers: meters / 1_000
    case .miles: meters / Self.mileMeters
    }
  }
}

private func roundedQuotient(_ numerator: Int64, _ denominator: Int64) -> Int64 {
  (numerator + denominator / 2) / denominator
}

private func parseDecimal(
  _ text: String, places: Int, limit: Int
) -> Result<Int, WeightRefusal> {
  let trimmed = text.trimmedWhitespace
  guard !trimmed.isEmpty else { return .failure(.empty) }
  let parts = trimmed.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
  guard parts.count <= 2, let whole = parts.first else { return .failure(.notANumber) }
  let fraction = parts.count == 2 ? parts[1] : ""
  let scale = (0..<places).reduce(1) { scale, _ in scale * 10 }
  guard !(whole.isEmpty && fraction.isEmpty),
    let units = whole.asciiNumber(limit: limit),
    let decimals = fraction.asciiNumber(limit: scale)
  else { return .failure(.notANumber) }
  guard fraction.utf8.count <= places else { return .failure(.tooPrecise) }
  let fractionScale = (fraction.utf8.count..<places).reduce(1) { scale, _ in scale * 10 }
  let value = units * scale + decimals * fractionScale
  return value <= limit ? .success(value) : .failure(.outOfRange)
}
