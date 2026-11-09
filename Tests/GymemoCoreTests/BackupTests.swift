import Foundation
import GymemoCore
import GymemoTestSupport
import Testing

@Suite struct BackupTests {
  private func sample() throws -> TrainingLog {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    try builder.exercise(2, "引用\"と\\と,", .other)
    try builder.set(1, "2026-11-05", "62.5", 8)
    try builder.set(2, "2026-11-09", "0", 12)
    try builder.apply(.setExerciseArchived(id: exerciseID(2), isArchived: true))
    try builder.apply(.writeMemo(day: try day("2026-11-09"), text: "一行目\n\t二行目 \"quote\" \\ 💪"))
    return builder.log
  }

  private func document(
    exercises: String = "", sets: String = "", memos: String = "", version: String = "1",
    format: String = "gymemo-backup"
  ) -> Data {
    Data(
      """
      {"format":"\(format)","formatVersion":\(version),"exercises":[\(exercises)],\
      "sets":[\(sets)],"memos":[\(memos)]}
      """.utf8)
  }

  private let bench =
    #"{"id":"67796D65-6D6F-4000-8000-000000000001","name":"ベンチプレス","bodyPart":"chest","archived":false}"#
  private let benchSet =
    #"{"id":"67796D65-6D6F-4000-8000-0000000000A1","exercise":"67796D65-6D6F-4000-8000-000000000001","day":"2026-11-09","weightKg":"60","reps":10}"#

  @Test func readsBackEverythingItWrites() throws {
    let log = try sample()
    let data = Backup.write(log)
    #expect(Backup.read(data) == .success(log))
    #expect(Backup.write(log) == data)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text.hasPrefix(#"{"format":"gymemo-backup","formatVersion":1,"#))
    #expect(Backup.read(Backup.write(.empty)) == .success(.empty))
  }

  @Test func readsAHandwrittenDocumentAndIgnoresUnknownKeys() throws {
    let data = document(
      exercises: bench.replacingOccurrences(of: "}", with: #","color":"red"}"#), sets: benchSet,
      memos: #"{"day":"2026-11-09","text":"好調"}"#)
    let log = try Backup.read(data).get()
    #expect(log.exercises.map(\.name.text) == ["ベンチプレス"])
    #expect(log.sets.map(\.weight.text) == ["60"])
    #expect(log.sets.map(\.reps.count) == [10])
    #expect(log.memo(on: try day("2026-11-09"))?.text == "好調")
  }

  @Test(arguments: [1, 2, 3, 4, 5, 6] as [UInt64])
  func readsBackTheLogOfEveryCommandSequence(seed: UInt64) throws {
    var generator = SeededGenerator(seed: seed)
    let texts = ["a\"b", "\\", "改行\nあり", "tab\tあり", "💪🏽", "カ\u{3099}", "{}[],:", "\u{2028}", "x"]
    var log = TrainingLog.empty
    for step in 0..<300 {
      let text = texts[Int.random(in: 0..<texts.count, using: &generator)] + "\(step % 17)"
      let exercise = exerciseID(UInt32.random(in: 1...8, using: &generator))
      let chosenDay =
        LocalDay.earliest.adding(days: Int.random(in: 0...110_000, using: &generator)) ?? .earliest
      let weight = Weight(hundredths: Int.random(in: 0...99_999, using: &generator)) ?? .bodyweight
      let count = Reps(Int.random(in: 1...999, using: &generator)) ?? .one
      let command: Command =
        switch Int.random(in: 0..<5, using: &generator) {
        case 0: .addExercise(id: exercise, name: text, bodyPart: .allCases[step % 7])
        case 1: .setExerciseArchived(id: exercise, isArchived: step % 2 == 0)
        case 2: .writeMemo(day: chosenDay, text: text)
        case 3: .deleteSet(id: setID(UInt32.random(in: 0..<300, using: &generator)))
        default:
          .logSet(
            id: setID(UInt32(step)), exerciseID: exercise, day: chosenDay, weight: weight,
            reps: count)
        }
      if case .success(let transition) = log.apply(command) { log = transition.log }
    }
    #expect(log.sets.count > 20)
    #expect(Backup.read(Backup.write(log)) == .success(log))
  }

  @Test func refusesDocumentsThatAreNotThisFormat() {
    #expect(Backup.read(Data()) == .failure(.notABackup))
    #expect(Backup.read(Data("[]".utf8)) == .failure(.notABackup))
    #expect(Backup.read(Data([0xFF, 0xFE, 0x00])) == .failure(.notABackup))
    #expect(Backup.read(document(format: "other")) == .failure(.notABackup))
    #expect(Backup.read(document(version: "2")) == .failure(.unsupportedVersion(2)))
    #expect(Backup.read(document(version: "0")) == .failure(.unsupportedVersion(0)))
    #expect(Backup.read(document(version: "\"1\"")) == .failure(.notABackup))
    #expect(
      Backup.read(Data(#"{"format":"gymemo-backup","formatVersion":1}"#.utf8))
        == .failure(.notABackup))
    #expect(Backup.read(Data(count: Backup.maximumBytes + 1)) == .failure(.tooLarge))
  }

  @Test func namesTheFirstRowItRefuses() {
    let badID = bench.replacingOccurrences(of: "67796D65", with: "not-hex!")
    #expect(Backup.read(document(exercises: badID)) == .failure(.invalidExercise(index: 0)))
    let badPart = bench.replacingOccurrences(of: "chest", with: "wings")
    #expect(
      Backup.read(document(exercises: bench + "," + badPart))
        == .failure(.invalidExercise(index: 1)))
    let unnamed = bench.replacingOccurrences(of: "ベンチプレス", with: "  ")
    #expect(Backup.read(document(exercises: unnamed)) == .failure(.invalidExercise(index: 0)))
    for (field, value) in [
      (#""day":"2026-11-09""#, #""day":"2026-02-30""#),
      (#""weightKg":"60""#, #""weightKg":"1000""#),
      (#""weightKg":"60""#, #""weightKg":"sixty""#), (#""reps":10"#, #""reps":0"#),
      (#""reps":10"#, #""reps":1000"#),
      (#""id":"67796D65-6D6F-4000-8000-0000000000A1""#, #""id":"x""#),
    ] {
      let broken = benchSet.replacingOccurrences(of: field, with: value)
      #expect(
        Backup.read(document(exercises: bench, sets: broken)) == .failure(.invalidSet(index: 0)))
    }
    #expect(
      Backup.read(document(memos: #"{"day":"2026-11-09","text":"  "}"#))
        == .failure(.invalidMemo(index: 0)))
    #expect(
      Backup.read(document(memos: #"{"day":"11/09","text":"a"}"#))
        == .failure(.invalidMemo(index: 0)))
    let memo = #"{"day":"2026-11-09","text":"a"}"#
    #expect(Backup.read(document(memos: memo + "," + memo)) == .failure(.invalidMemo(index: 1)))
  }

  @Test func refusesRowsThatBreakTheLog() {
    #expect(
      Backup.read(document(exercises: bench + "," + bench))
        == .failure(.integrity(.duplicateExerciseID)))
    #expect(Backup.read(document(sets: benchSet)) == .failure(.integrity(.unknownExercise)))
    #expect(
      Backup.read(document(exercises: bench, sets: benchSet + "," + benchSet))
        == .failure(.integrity(.duplicateSetID)))
  }

  @Test(arguments: [11, 12, 13, 14] as [UInt64])
  func survivesDamagedDocuments(seed: UInt64) throws {
    var generator = SeededGenerator(seed: seed)
    let original = [UInt8](Backup.write(try sample()))
    for _ in 0..<1500 {
      var bytes = original
      for _ in 0..<Int.random(in: 1...4, using: &generator) {
        let index = Int.random(in: 0..<bytes.count, using: &generator)
        switch Int.random(in: 0..<3, using: &generator) {
        case 0: bytes[index] = UInt8.random(in: 0...255, using: &generator)
        case 1: bytes.remove(at: index)
        default: bytes.insert(UInt8.random(in: 0...255, using: &generator), at: index)
        }
      }
      if case .success(let log) = Backup.read(Data(bytes)) {
        #expect(Backup.read(Backup.write(log)) == .success(log))
      }
    }
  }
}

@Suite struct CSVExportTests {
  private let labels = CSVLabels(
    day: "日付", exercise: "種目", bodyPart: "部位", set: "セット", weight: "重量(kg)", reps: "回数",
    bodyParts: [.chest: "胸", .back: "背中"])

  @Test func writesOneRowForEachSetByDayThenExerciseWithSetNumbers() throws {
    var builder = LogBuilder()
    try builder.exercise(1, "ベンチプレス", .chest)
    try builder.exercise(2, "懸垂", .back)
    try builder.set(1, "2026-11-09", "62.5", 8)
    try builder.set(2, "2026-11-09", "0", 12)
    try builder.set(1, "2026-11-09", "60", 10)
    try builder.set(1, "2026-11-05", "60", 10)
    let data = CSVExport.write(builder.log, labels: labels)
    #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
    let text = try #require(String(data: data.dropFirst(3), encoding: .utf8))
    #expect(
      text
        == [
          "日付,種目,部位,セット,重量(kg),回数",
          "2026-11-05,ベンチプレス,胸,1,60,10",
          "2026-11-09,ベンチプレス,胸,1,62.5,8",
          "2026-11-09,ベンチプレス,胸,2,60,10",
          "2026-11-09,懸垂,背中,1,0,12",
          "",
        ].joined(separator: "\r\n"))
  }

  @Test func quotesFieldsThatHoldSeparatorsOrQuotes() throws {
    var builder = LogBuilder()
    try builder.exercise(1, "プレス, \"重\"", .legs)
    try builder.set(1, "2026-11-09", "100", 5)
    let data = CSVExport.write(builder.log, labels: labels)
    let text = try #require(String(data: data.dropFirst(3), encoding: .utf8))
    #expect(text.contains("2026-11-09,\"プレス, \"\"重\"\"\",legs,1,100,5\r\n"))
  }

  @Test func writesOnlyTheHeaderForAnEmptyLog() throws {
    let data = CSVExport.write(.empty, labels: labels)
    #expect(String(data: data.dropFirst(3), encoding: .utf8) == "日付,種目,部位,セット,重量(kg),回数\r\n")
  }
}

@Suite struct StarterLogTests {
  @Test func offersCommonExercisesUnderTheGivenNamesAndNoSets() {
    let starter = TrainingLog.starter { "\($0)" }
    #expect(StarterExercise.allCases.count == 25)
    #expect(starter.exercises.map(\.name.text) == StarterExercise.allCases.map { "\($0)" })
    #expect(starter.exercises.map(\.id) == StarterExercise.allCases.map(\.id))
    #expect(starter.exercises.map(\.bodyPart) == StarterExercise.allCases.map(\.bodyPart))
    #expect(Set(StarterExercise.allCases.map(\.id)).count == 25)
    #expect(starter.sets.isEmpty)
    #expect(starter.memos.isEmpty)
    #expect(Set(starter.exercises.map(\.bodyPart)) == Set(BodyPart.allCases).subtracting([.other]))
    #expect(starter.exercises.allSatisfy { !$0.isArchived })
    #expect(starter.exercise(StarterExercise.squat.id)?.name.text == "squat")
    #expect(
      TrainingLog.make(exercises: starter.exercises, sets: [], memos: [:]) == .success(starter))
  }

  @Test func leavesOutAnExerciseWhoseNameTheLogRefuses() {
    let partial = TrainingLog.starter { exercise in
      switch exercise {
      case .squat: " "
      case .dips: "benchPress"
      default: "\(exercise)"
      }
    }
    #expect(partial.exercises.count == 23)
    #expect(partial.exercise(StarterExercise.squat.id) == nil)
    #expect(partial.exercise(StarterExercise.dips.id) == nil)
  }

  @Test func exposesTheRoundedEstimateInTenths() throws {
    let estimate = try #require(
      OneRepMax.estimate(weight: try kilograms("62.5"), reps: try reps(8)))
    #expect(estimate.tenths == 792)
    #expect(estimate.text == "79.2")
  }
}
