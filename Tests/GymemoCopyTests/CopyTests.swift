import Foundation
import GymemoCore
import Testing

@testable import GymemoCopy

private let languages = ["en", "ja", "zh-Hans", "zh-Hant"]

private func copy(_ language: String, locale: String? = nil) throws -> Copy {
  try #require(Copy(language: language, locale: Locale(identifier: locale ?? language)))
}

/// The placeholders of a format, each with its position, so two languages may order them differently.
private func placeholders(_ format: String) -> [String] {
  var found: [String] = []
  var next = 1
  for match in format.matches(of: /%(?:(\d+)\$)?(@|lld)/) {
    let position = match.1.flatMap { Int($0) } ?? next
    next = position + 1
    found.append("\(position):\(match.2)")
  }
  return found.sorted()
}

@Suite struct CatalogTests {
  @Test func offersExactlyTheSupportedLanguages() throws {
    #expect(Copy.languages == languages)
    for language in languages {
      #expect(try copy(language).language == language)
    }
    #expect(Copy(language: "fr", locale: Locale(identifier: "fr_FR")) == nil)
    #expect(languages.contains(Copy.current.language))
  }

  @Test(arguments: languages)
  func holdsEveryPlainString(language: String) throws {
    let copy = try copy(language)
    for key in CopyKey.allCases {
      let value = try #require(copy.stored(key.rawValue), "\(language) lacks \(key.rawValue)")
      #expect(!value.isEmpty, "\(language) leaves \(key.rawValue) empty")
      #expect(!value.contains("%"), "\(language) puts a placeholder in \(key.rawValue)")
      if key != .listSeparator {
        #expect(value == value.trimmingCharacters(in: .whitespacesAndNewlines))
      }
      #expect(copy[key] == value)
    }
  }

  @Test(arguments: ["ja", "zh-Hans", "zh-Hant"])
  func translatesEveryPlainStringAwayFromEnglish(language: String) throws {
    let english = try copy("en")
    let copy = try copy(language)
    for key in CopyKey.allCases where key != .kilogramUnit {
      #expect(copy[key] != english[key], "\(language) repeats the English \(key.rawValue)")
    }
  }

  @Test(arguments: languages)
  func keepsThePlaceholdersOfEveryFormat(language: String) throws {
    let english = try copy("en")
    let copy = try copy(language)
    for key in FormatKey.allCases where !FormatKey.plural.contains(key) {
      let value = try #require(copy.stored(key.rawValue), "\(language) lacks \(key.rawValue)")
      let source = try #require(english.stored(key.rawValue))
      #expect(!placeholders(source).isEmpty, "\(key.rawValue) formats nothing")
      #expect(placeholders(value) == placeholders(source), "\(language) changes \(key.rawValue)")
    }
  }

  @Test func theCatalogFileHoldsExactlyTheKeysOfTheCodeFullyTranslated() throws {
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: "Sources/GymemoCopy/Localizable.xcstrings")
    let catalog = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    #expect(catalog["sourceLanguage"] as? String == "en")
    let strings = try #require(catalog["strings"] as? [String: [String: Any]])
    let known = CopyKey.allCases.map(\.rawValue) + FormatKey.allCases.map(\.rawValue)
    #expect(Set(known).count == known.count)
    #expect(Set(strings.keys) == Set(known))
    for (key, entry) in strings {
      let localizations = try #require(entry["localizations"] as? [String: [String: Any]])
      #expect(Set(localizations.keys) == Set(languages), "\(key) lacks a language")
      for (language, localization) in localizations {
        let units = try units(of: localization)
        #expect(!units.isEmpty, "\(key) holds no \(language) text")
        for unit in units {
          #expect(unit["state"] as? String == "translated", "\(key) is unfinished in \(language)")
          #expect((unit["value"] as? String)?.isEmpty == false, "\(key) is empty in \(language)")
        }
      }
    }
  }

  /// The string units of one localization, which has either one value or one value for each plural category.
  private func units(of localization: [String: Any]) throws -> [[String: Any]] {
    if let unit = localization["stringUnit"] as? [String: Any] { return [unit] }
    let variations = try #require(localization["variations"] as? [String: Any])
    let plural = try #require(variations["plural"] as? [String: [String: Any]])
    #expect(plural["other"] != nil)
    return plural.values.compactMap { $0["stringUnit"] as? [String: Any] }
  }
}

@Suite struct CopyTextTests {
  private let heavy = Weight(hundredths: 6250) ?? .bodyweight
  private let eight = Reps(8) ?? .one

  @Test func countsWithTheGrammarOfEachLanguage() throws {
    let english = try copy("en", locale: "en_US")
    #expect(english.setCount(1) == "1 set")
    #expect(english.setCount(5) == "5 sets")
    #expect(english.setCount(0) == "0 sets")
    #expect(english.dayCount(1) == "1 day")
    #expect(english.dayCount(3) == "3 days")
    #expect(english.repCount(1) == "1 rep")
    #expect(english.repCount(12) == "12 reps")
    let japanese = try copy("ja", locale: "ja_JP")
    #expect(japanese.setCount(5) == "5セット")
    #expect(japanese.dayCount(1) == "1日")
    #expect(japanese.repCount(12) == "12回")
    #expect(try copy("zh-Hans", locale: "zh_Hans_CN").setCount(5) == "5 组")
    #expect(try copy("zh-Hant", locale: "zh_Hant_TW").setCount(5) == "5 組")
    #expect(try copy("zh-Hans", locale: "zh_Hans_CN").dayCount(3) == "3 天")
  }

  @Test func writesSetsInEachLanguage() throws {
    #expect(try copy("en", locale: "en_US").set(weight: heavy, reps: eight) == "62.5 kg × 8")
    #expect(
      try copy("en", locale: "en_US").set(weight: .bodyweight, reps: .one) == "Bodyweight × 1")
    #expect(try copy("ja", locale: "ja_JP").set(weight: heavy, reps: eight) == "62.5 kg × 8回")
    #expect(try copy("ja", locale: "ja_JP").set(weight: .bodyweight, reps: eight) == "自重 × 8回")
    #expect(
      try copy("zh-Hans", locale: "zh_Hans_CN").set(weight: heavy, reps: eight) == "62.5 kg × 8 次")
    #expect(
      try copy("zh-Hant", locale: "zh_Hant_TW").set(weight: heavy, reps: eight) == "62.5 kg × 8 次")
  }

  @Test func writesNumbersWithTheDecimalSeparatorOfTheRegion() throws {
    let german = try copy("en", locale: "de_DE")
    #expect(german.weightField(heavy) == "62,5")
    #expect(german.set(weight: heavy, reps: eight) == "62,5 kg × 8")
    #expect(german.load(Weight(hundredths: 99_999) ?? .bodyweight) == "999,99 kg")
    let american = try copy("en", locale: "en_US")
    #expect(american.weightField(heavy) == "62.5")
    #expect(american.weightField(Weight(hundredths: 6000) ?? .bodyweight) == "60")
    #expect(american.weightField(Weight(hundredths: 100_00) ?? .bodyweight) == "100")
    #expect(american.weightField(.bodyweight).isEmpty)
    #expect(american.load(.bodyweight) == "Bodyweight")
    for hundredths in [0, 5, 50, 125, 6250, 99_999] {
      let weight = try #require(Weight(hundredths: hundredths))
      #expect(Weight.parse(german.weightText(weight)) == .success(weight))
      #expect(Weight.parse(american.weightText(weight)) == .success(weight))
    }
  }

  @Test func writesScores() throws {
    let english = try copy("en", locale: "en_US")
    let estimate = try #require(OneRepMax.estimate(weight: heavy, reps: eight))
    #expect(english.score(.oneRepMax(estimate)) == "79.2 kg")
    #expect(english.score(.reps(eight)) == "8 reps")
    #expect(english.scoreLine(.oneRepMax(estimate)) == "Estimated 1RM 79.2 kg")
    #expect(english.scoreLine(.reps(.one)) == "Most Reps 1")
    #expect(try copy("ja", locale: "ja_JP").scoreLine(.reps(eight)) == "最高回数 8回")
    #expect(try copy("zh-Hans", locale: "zh_Hans_CN").scoreLine(.reps(eight)) == "最多次数 8 次")
    #expect(try copy("en", locale: "de_DE").score(.oneRepMax(estimate)) == "79,2 kg")
    #expect(try copy("ja", locale: "ja_JP").scoreLine(.oneRepMax(estimate)) == "推定1RM 79.2 kg")
  }

  @Test func writesTheWeeklyHeadline() throws {
    let english = try copy("en", locale: "en_US")
    #expect(english.weeklyHeadline(thisWeek: 1, lastWeek: 3) == "1 day this week, 3 days last week")
    #expect(english.weeklyHeadline(thisWeek: 2, lastWeek: nil) == "2 days this week")
    #expect(
      try copy("ja", locale: "ja_JP").weeklyHeadline(thisWeek: 1, lastWeek: 3) == "今週1日、先週3日")
    #expect(
      try copy("zh-Hans", locale: "zh_Hans_CN").weeklyHeadline(thisWeek: 1, lastWeek: 3)
        == "本周 1 天，上周 3 天")
  }

  @Test func writesDaysInTheCalendarOfTheLocale() throws {
    let day = try #require(LocalDay(iso: "2026-11-09"))
    let english = try copy("en", locale: "en_US")
    for part in ["Mon", "Nov", "9", "2026"] {
      #expect(english.day(day, .long).contains(part))
    }
    #expect(!english.day(day, .short).contains("2026"))
    #expect(english.day(day, .short).contains("Nov"))
    #expect(english.day(day, .axis) == "11/9")
    let japanese = try copy("ja", locale: "ja_JP")
    #expect(japanese.day(day, .long).contains("2026年11月9日"))
    #expect(japanese.day(day, .long).contains("月"))
    #expect(japanese.day(day, .axis) == "11/9")
    #expect(try copy("zh-Hans", locale: "zh_Hans_CN").day(day, .long).contains("2026年11月9日"))
    #expect(try copy("en", locale: "en_GB").day(day, .axis) == "09/11")
    let lastDay = try #require(LocalDay(iso: "2026-12-31"))
    #expect(english.day(lastDay, .long).contains("31"))
    #expect(english.day(lastDay, .long).contains("2026"))
  }

  @Test func speaksASetWithItsUnitsSpelledOut() throws {
    let english = try copy("en", locale: "en_US")
    #expect(
      english.spokenSet(weight: heavy, reps: eight, number: 1, isBest: true)
        == "Set 1, 62.5 kilograms, 8 reps, Personal Best")
    #expect(
      english.spokenSet(weight: .bodyweight, reps: .one, number: 2, isBest: false)
        == "Set 2, Bodyweight, 1 rep")
    #expect(
      try copy("ja", locale: "ja_JP").spokenSet(weight: heavy, reps: eight, number: 1, isBest: true)
        == "1セット目、62.5 キログラム、8回、自己ベスト")
  }

  @Test(arguments: languages)
  func namesEveryStarterExerciseAndBodyPartWithoutACollision(language: String) throws {
    let copy = try copy(language)
    let starter = TrainingLog.starter(named: copy.starterName)
    #expect(starter.exercises.count == StarterExercise.allCases.count)
    #expect(Set(BodyPart.allCases.map(copy.bodyPart)).count == BodyPart.allCases.count)
    let labels = copy.csvLabels
    #expect(labels.bodyParts.count == BodyPart.allCases.count)
    for heading in [
      labels.day, labels.exercise, labels.bodyPart, labels.set, labels.weight, labels.reps,
    ] {
      #expect(!heading.isEmpty && !heading.contains(",") && !heading.contains("\""))
    }
  }

  @Test(arguments: languages)
  func explainsEveryRefusal(language: String) throws {
    let copy = try copy(language)
    let entries: [SetEntryRefusal] = [
      .weight(.notANumber), .weight(.tooPrecise), .weight(.outOfRange), .weight(.empty),
      .reps(.empty), .reps(.notANumber), .reps(.outOfRange),
    ]
    #expect(entries.allSatisfy { !copy.problem(entry: $0).isEmpty })
    #expect(copy.problem(entry: .reps(.empty)) != copy.problem(entry: .reps(.outOfRange)))
    let refusals: [Refusal] = [
      .exerciseName(.empty), .exerciseName(.tooLong), .exerciseName(.controlCharacter),
      .duplicateExerciseName, .duplicateIdentifier, .unknownExercise, .exerciseHasSets, .unknownSet,
      .memo(.tooLong), .memo(.controlCharacter), .full,
    ]
    #expect(refusals.allSatisfy { !copy.problem(exercise: $0).isEmpty })
    #expect(refusals.allSatisfy { !copy.problem(note: $0).isEmpty })
    #expect(copy.problem(exercise: .exerciseName(.tooLong)).contains("40"))
    #expect(copy.problem(note: .memo(.tooLong)).contains("2,000"))
    let backups: [BackupRefusal] = [
      .tooLarge, .notABackup, .unsupportedVersion(0), .unsupportedVersion(2),
      .invalidExercise(index: 0), .invalidSet(index: 4), .invalidMemo(index: 9),
      .integrity(.duplicateSetID),
    ]
    #expect(Set(backups.map(copy.problem(backup:))).count == backups.count)
    #expect(copy.problem(backup: .invalidSet(index: 4)).contains("5"))
  }

  @Test func writesTheRemainingSentences() throws {
    let english = try copy("en", locale: "en_US")
    let day = try #require(LocalDay(iso: "2026-11-09"))
    let name = try ExerciseName.parse("Bench Press").get()
    #expect(english.deleteQuestion(name) == "Delete “Bench Press”?")
    #expect(english.version(marketing: "1.0", build: "1") == "Version 1.0 (1)")
    #expect(
      english.replaceMessage(current: 1, incoming: 12)
        == "Your 1 set will be deleted and replaced with the 12 sets in the backup. You can't undo the replacement."
    )
    #expect(
      english.saveFailedMessage(code: 13) == "Your records are unchanged. Try again. (Code 13)")
    #expect(english.failureCode(-4) == "Code -4")
    #expect(english.heaviest(heavy) == "Heaviest Weight 62.5 kg")
    #expect(english.progressHeading(.oneRepMax) == "Estimated 1RM over Time")
    #expect(english.noteCaption(day).hasPrefix("Note for "))
    #expect(english.lastLogged(day).hasPrefix("Last logged "))
    #expect(english.weekLabel(startingOn: day).hasPrefix("Week of "))
    #expect(
      english.historyRow(exercises: ["Squat", "Bench Press"], setCount: 5)
        == "Squat, Bench Press · 5 sets")
    #expect(
      english.previous(day: day, sets: [(heavy, eight), (heavy, .one)]).hasSuffix(
        ": 62.5 kg × 8, 62.5 kg × 1"))
    #expect(english.setOnDay(weight: heavy, reps: eight, day: day).hasPrefix("62.5 kg × 8 on "))
  }
}
