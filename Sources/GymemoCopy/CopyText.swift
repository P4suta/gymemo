import Foundation
import GymemoCore
import GymemoKit

/// How much of a day a text shows.
public enum DayStyle: Sendable {
  /// The year, month, day, and weekday.
  case long
  /// The month, day, and weekday.
  case short
  /// The month and day as numbers, for a chart axis.
  case axis
  /// The month and year, for the header of a month in the history.
  case month
}

extension Copy {
  // MARK: Days

  /// A day in the locale's own calendar and order.
  /// The text formats `LocalDay.noonUTC` in UTC, where it always falls on its own day.
  public func day(_ day: LocalDay, _ style: DayStyle) -> String {
    day.noonUTC.formatted(dateStyle(style))
  }

  /// The locale's calendar in UTC, for a date picker or a chart that shows `LocalDay.noonUTC`.
  public var calendar: Calendar {
    var calendar = locale.calendar
    calendar.timeZone = .gmt
    return calendar
  }

  /// The format of `day(_:_:)`, for a chart axis that formats its own dates.
  public func dateStyle(_ style: DayStyle) -> Date.FormatStyle {
    let base = Date.FormatStyle(
      date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: .gmt)
    return switch style {
    case .long: base.year().month(.abbreviated).day().weekday(.abbreviated)
    case .short: base.month(.abbreviated).day().weekday(.abbreviated)
    case .axis: base.month(.defaultDigits).day()
    case .month: base.year().month(.wide)
    }
  }

  // MARK: Loads, sets, and scores

  /// A weight as a number, such as `62.5`, with the region's decimal separator.
  public func weightText(_ weight: Weight) -> String {
    decimal(weight.hundredths, dividedBy: 100, fractionDigits: 2)
  }

  /// The text that a weight field starts with, which is empty for the body alone.
  /// The digits stay ASCII, because `Weight.parse` reads only ASCII digits.
  public func weightField(_ weight: Weight) -> String {
    guard !weight.isBodyweight else { return "" }
    return weight.text.replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
  }

  /// Such as `62.5 kg`, or the word for the body alone.
  public func load(_ weight: Weight) -> String {
    weight.isBodyweight ? self[.bodyweight] : format(.loadKilograms, weightText(weight))
  }

  /// Such as `62.5 kg × 8`.
  public func set(weight: Weight, reps: Reps) -> String {
    format(.setSummary, load(weight), reps.count)
  }

  public func set(_ set: LoggedSet) -> String {
    self.set(weight: set.weight, reps: set.reps)
  }

  public func sets(_ sets: [LoggedSet]) -> String {
    join(sets.map(set))
  }

  public func setCount(_ count: Int) -> String {
    format(.setsCount, count)
  }

  public func dayCount(_ count: Int) -> String {
    format(.daysCount, count)
  }

  public func repCount(_ count: Int) -> String {
    format(.repsCount, count)
  }

  public func score(_ score: Score) -> String {
    switch score {
    case .oneRepMax(let estimate):
      format(.loadKilograms, decimal(estimate.tenths, dividedBy: 10, fractionDigits: 1))
    case .reps(let reps): repCount(reps.count)
    }
  }

  public func scoreName(_ kind: ScoreKind) -> String {
    switch kind {
    case .oneRepMax: self[.estimatedOneRepMax]
    case .reps: self[.mostReps]
    }
  }

  /// A score with its name, such as `Estimated 1RM 79.2 kg` or `Most reps 9`.
  public func scoreLine(_ score: Score) -> String {
    switch score {
    case .oneRepMax: format(.oneRepMaxLine, self.score(score))
    case .reps(let reps): format(.mostRepsLine, reps.count)
    }
  }

  /// What VoiceOver reads for a set, with its units spelled out.
  public func spokenSet(weight: Weight, reps: Reps, number: Int, isBest: Bool) -> String {
    let load =
      weight.isBodyweight ? self[.bodyweight] : format(.kilogramsSpoken, weightText(weight))
    let parts = [format(.setNumber, number), load, repCount(reps.count)]
    return join(isBest ? parts + [self[.personalBest]] : parts)
  }

  // MARK: Sentences with values

  /// The previous session of an exercise, such as `Last time on Mon, Nov 2: 62.5 kg × 8`.
  public func previous(day: LocalDay, sets: [(weight: Weight, reps: Reps)]) -> String {
    format(.previousSession, self.day(day, .short), join(sets.map { set(weight: $0, reps: $1) }))
  }

  public func previous(_ session: Session) -> String {
    previous(day: session.day, sets: session.sets.map { ($0.weight, $0.reps) })
  }

  /// A day's exercises and its number of sets, for one row of the history.
  public func historyRow(exercises: [String], setCount: Int) -> String {
    format(.historyRow, join(exercises), self.setCount(setCount))
  }

  /// The training days of the current week, and of the week before it when the chart shows one.
  public func weeklyHeadline(thisWeek: Int, lastWeek: Int?) -> String {
    guard let lastWeek else { return format(.weeklyHeadlineSingle, dayCount(thisWeek)) }
    return format(.weeklyHeadline, dayCount(thisWeek), dayCount(lastWeek))
  }

  public func weekLabel(startingOn day: LocalDay) -> String {
    format(.weekOf, self.day(day, .short))
  }

  public func lastLogged(_ day: LocalDay) -> String {
    format(.lastLogged, self.day(day, .long))
  }

  /// A set with its day, such as `62.5 kg × 8 on Mon, Nov 9, 2026`.
  public func setOnDay(weight: Weight, reps: Reps, day: LocalDay) -> String {
    format(.setOnDay, set(weight: weight, reps: reps), self.day(day, .long))
  }

  public func heaviest(_ weight: Weight) -> String {
    format(.heaviestWeight, load(weight))
  }

  public func progressHeading(_ kind: ScoreKind) -> String {
    format(.overTime, scoreName(kind))
  }

  public func deleteQuestion(_ name: ExerciseName) -> String {
    format(.deleteExerciseQuestion, name.text)
  }

  public func version(marketing: String, build: String) -> String {
    format(.version, marketing, build)
  }

  public func replaceMessage(current: Int, incoming: Int) -> String {
    format(.replaceMessage, setCount(current), setCount(incoming))
  }

  public func saveFailedMessage(code: Int32) -> String {
    format(.saveFailedMessage, Int(code))
  }

  public func failureCode(_ code: Int32) -> String {
    format(.failureCode, Int(code))
  }

  // MARK: Names

  public func bodyPart(_ part: BodyPart) -> String {
    switch part {
    case .chest: self[.chest]
    case .back: self[.back]
    case .legs: self[.legs]
    case .shoulders: self[.shoulders]
    case .arms: self[.arms]
    case .abdominals: self[.abdominals]
    case .other: self[.otherBodyPart]
    }
  }

  public func starterName(_ exercise: StarterExercise) -> String {
    let key: CopyKey =
      switch exercise {
      case .benchPress: .starterBenchPress
      case .inclineBenchPress: .starterInclineBenchPress
      case .dumbbellPress: .starterDumbbellPress
      case .dumbbellFly: .starterDumbbellFly
      case .chestPress: .starterChestPress
      case .dips: .starterDips
      case .deadlift: .starterDeadlift
      case .pullUp: .starterPullUp
      case .latPulldown: .starterLatPulldown
      case .bentOverRow: .starterBentOverRow
      case .seatedRow: .starterSeatedRow
      case .squat: .starterSquat
      case .legPress: .starterLegPress
      case .legExtension: .starterLegExtension
      case .legCurl: .starterLegCurl
      case .romanianDeadlift: .starterRomanianDeadlift
      case .calfRaise: .starterCalfRaise
      case .shoulderPress: .starterShoulderPress
      case .lateralRaise: .starterLateralRaise
      case .rearDeltRaise: .starterRearDeltRaise
      case .bicepsCurl: .starterBicepsCurl
      case .hammerCurl: .starterHammerCurl
      case .tricepsPushdown: .starterTricepsPushdown
      case .crunch: .starterCrunch
      case .legRaise: .starterLegRaise
      }
    return self[key]
  }

  public var csvLabels: CSVLabels {
    CSVLabels(
      day: self[.csvDate], exercise: self[.csvExercise], bodyPart: self[.bodyPart],
      set: self[.csvSet], weight: self[.csvWeight], reps: self[.reps],
      bodyParts: Dictionary(
        BodyPart.allCases.map { ($0, bodyPart($0)) }, uniquingKeysWith: { first, _ in first }))
  }

  // MARK: Refusals

  /// What is wrong with the inputs of a set, and how to fix them.
  public func problem(entry refusal: SetEntryRefusal) -> String {
    switch refusal {
    case .weight: self[.weightProblem]
    case .reps(.empty): self[.repsMissing]
    case .reps: self[.repsProblem]
    }
  }

  /// Why the log refused an exercise, and how to fix it.
  public func problem(exercise refusal: Refusal) -> String {
    switch refusal {
    case .exerciseName(.empty): self[.nameMissing]
    case .exerciseName(.tooLong): format(.nameTooLong, ExerciseName.maximumLength)
    case .exerciseName(.controlCharacter): self[.nameLinesProblem]
    case .duplicateExerciseName: self[.nameDuplicate]
    case .exerciseHasSets: self[.exerciseHasSets]
    case .full: self[.exerciseLimit]
    case .duplicateIdentifier, .unknownExercise, .unknownSet, .memo: self[.exerciseNotSaved]
    }
  }

  /// Why the log refused a note, and how to fix it.
  public func problem(note refusal: Refusal) -> String {
    switch refusal {
    case .memo(.tooLong): format(.noteTooLong, Memo.maximumLength)
    default: self[.noteCharactersProblem]
    }
  }

  /// Why a file isn't a backup that the app reads.
  public func problem(backup refusal: BackupRefusal) -> String {
    switch refusal {
    case .tooLarge: self[.backupTooLarge]
    case .notABackup: self[.backupNotABackup]
    case .unsupportedVersion(let version) where version > Backup.formatVersion: self[.backupNewer]
    case .unsupportedVersion: self[.backupUnsupported]
    case .invalidExercise(let index): format(.backupExerciseUnreadable, index + 1)
    case .invalidSet(let index): format(.backupSetUnreadable, index + 1)
    case .invalidMemo(let index): format(.backupNoteUnreadable, index + 1)
    case .integrity: self[.backupDamaged]
    }
  }
}
