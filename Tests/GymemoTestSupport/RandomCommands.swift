import Foundation
import GymemoCore

public func uuid(_ number: UInt32) -> UUID {
  let bytes = withUnsafeBytes(of: number.bigEndian, Array.init)
  return UUID(
    uuid: (
      0x67, 0x79, 0x6D, 0x65, 0x6D, 0x6F, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00,
      bytes[0], bytes[1], bytes[2], bytes[3]
    ))
}

public func exerciseID(_ number: UInt32) -> ExerciseID { ExerciseID(uuid(number)) }

public func setID(_ number: UInt32) -> SetID { SetID(uuid(number)) }

/// SplitMix64, so a seed names one reproducible sequence.
public struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  public init(seed: UInt64) {
    state = seed
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}

/// Commands over a few exercises, sets, and days, so that sequences collide, repeat, and refer to missing rows.
public enum RandomCommand {
  private static let texts = [
    "ベンチプレス", "スクワット", "デッドリフト", "懸垂", "", " ", "ベンチ\nプレス", "引用\"と\\", "カ\u{3099}",
  ]

  public static func next(using generator: inout SeededGenerator) -> Command {
    let exercise = exerciseID(UInt32.random(in: 1...6, using: &generator))
    let set = setID(UInt32.random(in: 1...40, using: &generator))
    let text = texts[Int.random(in: 0..<texts.count, using: &generator)]
    let part = BodyPart.allCases[Int.random(in: 0..<BodyPart.allCases.count, using: &generator)]
    let day =
      LocalDay.earliest.adding(days: Int.random(in: 46_000...46_005, using: &generator))
      ?? .earliest
    let weight = Weight(hundredths: Int.random(in: 0...3, using: &generator) * 2500) ?? .bodyweight
    let reps = Reps(Int.random(in: 1...12, using: &generator)) ?? .one
    switch Int.random(in: 0..<10, using: &generator) {
    case 0: return .addExercise(id: exercise, name: text, bodyPart: part)
    case 1: return .editExercise(id: exercise, name: text, bodyPart: part)
    case 2: return .setExerciseArchived(id: exercise, isArchived: Bool.random(using: &generator))
    case 3: return .deleteExercise(id: exercise)
    case 4, 5, 6:
      return .logSet(id: set, exerciseID: exercise, day: day, weight: weight, reps: reps)
    case 7: return .editSet(id: set, weight: weight, reps: reps)
    case 8: return .deleteSet(id: set)
    default: return .writeMemo(day: day, text: text)
    }
  }
}
