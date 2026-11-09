import Foundation
import GymemoCore
import GymemoKit

/// The Japanese text of days, loads, and scores.
/// Days format in UTC, where `LocalDay.noonUTC` always falls on its own day.
enum Format {
  private static let locale = Locale(identifier: "ja_JP")

  private static let dayStyle: Date.FormatStyle = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return Date.FormatStyle(
      date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: .gmt)
  }()

  /// Such as `2026年11月9日(月)`.
  static func longDay(_ day: LocalDay) -> String {
    day.noonUTC.formatted(dayStyle.year().month().day().weekday(.abbreviated))
  }

  /// Such as `11月9日(月)`.
  static func shortDay(_ day: LocalDay) -> String {
    day.noonUTC.formatted(dayStyle.month().day().weekday(.abbreviated))
  }

  /// Such as `11/9`.
  static func axisDay(_ day: LocalDay) -> String {
    "\(day.month)/\(day.day)"
  }

  static func load(_ weight: Weight) -> String {
    weight.isBodyweight ? "自重" : "\(weight.text) kg"
  }

  /// Such as `62.5 kg × 8回`.
  static func set(_ set: LoggedSet) -> String {
    "\(load(set.weight)) × \(set.reps.count)回"
  }

  static func score(_ score: Score) -> String {
    switch score {
    case .oneRepMax(let estimate): "\(estimate.text) kg"
    case .reps(let reps): "\(reps.count)回"
    }
  }

  static func scoreName(_ kind: ScoreKind) -> String {
    switch kind {
    case .oneRepMax: "推定1RM"
    case .reps: "最高回数"
    }
  }

  static func bodyPart(_ part: BodyPart) -> String {
    switch part {
    case .chest: "胸"
    case .back: "背中"
    case .legs: "脚"
    case .shoulders: "肩"
    case .arms: "腕"
    case .abdominals: "腹"
    case .other: "ほか"
    }
  }

  /// What VoiceOver reads for a set, with units spelled out.
  static func spokenSet(_ set: LoggedSet, number: Int, isBest: Bool) -> String {
    let load = set.weight.isBodyweight ? "自重" : "\(set.weight.text)キログラム"
    return "\(number)セット目、\(load)、\(set.reps.count)回" + (isBest ? "、自己ベスト" : "")
  }
}
