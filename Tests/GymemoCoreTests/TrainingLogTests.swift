import Foundation
import GymemoCore
import Testing

@Suite struct TrainingLogCommandTests {
  private let bench = Command.addExercise(id: exerciseID(1), name: " ベンチプレス ", bodyPart: .chest)
  private let squat = Command.addExercise(id: exerciseID(2), name: "スクワット", bodyPart: .legs)

  @Test func addsExercisesInOrderWithTrimmedNames() throws {
    let first = try TrainingLog.empty.apply(bench).get()
    let stored = try #require(first.log.exercise(exerciseID(1)))
    #expect(stored.name.text == "ベンチプレス")
    #expect(stored.bodyPart == .chest)
    #expect(!stored.isArchived)
    #expect(first.changes == [.putExercise(stored)])
    let second = try first.log.applying(squat)
    #expect(second.exercises.map(\.id) == [exerciseID(1), exerciseID(2)])
  }

  @Test func refusesExercisesThatCollideOrHaveNoName() throws {
    let log = try TrainingLog.empty.applying(bench)
    let sameName = Command.addExercise(id: exerciseID(3), name: "ベンチプレス\n", bodyPart: .arms)
    #expect(log.apply(sameName) == .failure(.duplicateExerciseName))
    let sameID = Command.addExercise(id: exerciseID(1), name: "ダンベルプレス", bodyPart: .chest)
    #expect(log.apply(sameID) == .failure(.duplicateIdentifier))
    let unnamed = Command.addExercise(id: exerciseID(3), name: "  ", bodyPart: .chest)
    #expect(log.apply(unnamed) == .failure(.exerciseName(.empty)))
  }

  @Test func editsAnExerciseWithoutMovingIt() throws {
    let log = try TrainingLog.empty.applying(bench, squat)
    let renamed = try log.apply(
      .editExercise(id: exerciseID(1), name: "ベンチ", bodyPart: .arms)
    ).get()
    #expect(renamed.log.exercises.map(\.name.text) == ["ベンチ", "スクワット"])
    #expect(renamed.log.exercise(exerciseID(1))?.bodyPart == .arms)
    #expect(renamed.changes.count == 1)
    let unchanged = try log.apply(
      .editExercise(id: exerciseID(1), name: "ベンチプレス", bodyPart: .chest)
    ).get()
    #expect(unchanged.changes.isEmpty)
    #expect(unchanged.log == log)
    #expect(
      log.apply(.editExercise(id: exerciseID(1), name: "スクワット", bodyPart: .chest))
        == .failure(.duplicateExerciseName))
    #expect(
      log.apply(.editExercise(id: exerciseID(9), name: "プランク", bodyPart: .abdominals))
        == .failure(.unknownExercise))
    #expect(
      log.apply(.editExercise(id: exerciseID(1), name: "", bodyPart: .chest))
        == .failure(.exerciseName(.empty)))
  }

  @Test func archivesAndRestoresAnExercise() throws {
    let log = try TrainingLog.empty.applying(bench)
    let archived = try log.apply(.setExerciseArchived(id: exerciseID(1), isArchived: true)).get()
    #expect(archived.log.exercise(exerciseID(1))?.isArchived == true)
    #expect(archived.changes.count == 1)
    let again = try archived.log.apply(
      .setExerciseArchived(id: exerciseID(1), isArchived: true)
    ).get()
    #expect(again.changes.isEmpty)
    #expect(
      log.apply(.setExerciseArchived(id: exerciseID(9), isArchived: true))
        == .failure(.unknownExercise))
  }

  @Test func deletesOnlyAnExerciseWithoutSets() throws {
    let logged = try TrainingLog.empty.applying(
      bench, squat,
      .logSet(
        id: setID(1), exerciseID: exerciseID(1), day: day("2026-11-09"),
        weight: kilograms("60"), reps: reps(10)))
    #expect(logged.apply(.deleteExercise(id: exerciseID(1))) == .failure(.exerciseHasSets))
    #expect(logged.apply(.deleteExercise(id: exerciseID(9))) == .failure(.unknownExercise))
    let deleted = try logged.apply(.deleteExercise(id: exerciseID(2))).get()
    #expect(deleted.log.exercises.map(\.id) == [exerciseID(1)])
    #expect(deleted.changes == [.removeExercise(exerciseID(2))])
  }

  @Test func logsEditsAndDeletesSets() throws {
    let monday = try day("2026-11-09")
    let base = try TrainingLog.empty.applying(bench)
    let first = Command.logSet(
      id: setID(1), exerciseID: exerciseID(1), day: monday, weight: try kilograms("60"),
      reps: try reps(10))
    let logged = try base.apply(first).get()
    let stored = try #require(logged.log.set(setID(1)))
    #expect(stored.weight.text == "60")
    #expect(stored.reps.count == 10)
    #expect(stored.day == monday)
    #expect(logged.changes == [.putSet(stored)])
    #expect(logged.log.apply(first) == .failure(.duplicateIdentifier))
    let stray = Command.logSet(
      id: setID(2), exerciseID: exerciseID(9), day: monday, weight: .bodyweight,
      reps: try reps(1))
    #expect(logged.log.apply(stray) == .failure(.unknownExercise))

    let edit = Command.editSet(id: setID(1), weight: try kilograms("62.5"), reps: try reps(8))
    let edited = try logged.log.apply(edit).get()
    #expect(edited.log.set(setID(1))?.weight.text == "62.5")
    #expect(edited.log.set(setID(1))?.reps.count == 8)
    #expect(edited.changes.count == 1)
    #expect(try edited.log.apply(edit).get().changes.isEmpty)
    #expect(
      logged.log.apply(.editSet(id: setID(9), weight: .bodyweight, reps: try reps(1)))
        == .failure(.unknownSet))

    let deleted = try edited.log.apply(.deleteSet(id: setID(1))).get()
    #expect(deleted.log.sets.isEmpty)
    #expect(deleted.changes == [.removeSet(setID(1))])
    #expect(deleted.log.apply(.deleteSet(id: setID(1))) == .failure(.unknownSet))
  }

  @Test func writesReplacesAndClearsADayMemo() throws {
    let monday = try day("2026-11-09")
    let written = try TrainingLog.empty.apply(.writeMemo(day: monday, text: " 肩が重い\n")).get()
    let memo = try #require(written.log.memo(on: monday))
    #expect(memo.text == "肩が重い")
    #expect(written.changes == [.putMemo(monday, memo)])
    #expect(try written.log.apply(.writeMemo(day: monday, text: "肩が重い")).get().changes.isEmpty)
    let cleared = try written.log.apply(.writeMemo(day: monday, text: "  ")).get()
    #expect(cleared.log.memo(on: monday) == nil)
    #expect(cleared.changes == [.removeMemo(monday)])
    #expect(try cleared.log.apply(.writeMemo(day: monday, text: "")).get().changes.isEmpty)
    let long = String(repeating: "あ", count: Memo.maximumLength + 1)
    #expect(
      TrainingLog.empty.apply(.writeMemo(day: monday, text: long)) == .failure(.memo(.tooLong)))
    #expect(
      TrainingLog.empty.apply(.writeMemo(day: monday, text: "a\u{0}b"))
        == .failure(.memo(.controlCharacter)))
    let lines = try TrainingLog.empty.applying(.writeMemo(day: monday, text: "一行目\n二行目"))
    #expect(lines.memo(on: monday)?.text == "一行目\n二行目")
  }

  @Test func replacesTheWholeLog() throws {
    let replacement = try TrainingLog.empty.applying(squat)
    let replaced = try TrainingLog.empty.applying(bench).apply(.replaceAll(replacement)).get()
    #expect(replaced.log == replacement)
    #expect(replaced.changes == [.replaceAll(replacement)])
  }

  @Test func refusesRowsThatBreakTheLog() throws {
    let log = try TrainingLog.empty.applying(
      bench, squat,
      .logSet(
        id: setID(1), exerciseID: exerciseID(1), day: day("2026-11-09"),
        weight: kilograms("60"), reps: reps(10)))
    let exercises = log.exercises
    let sets = log.sets
    #expect(TrainingLog.make(exercises: exercises, sets: sets, memos: [:]) == .success(log))
    #expect(
      TrainingLog.make(exercises: exercises + [exercises[0]], sets: sets, memos: [:])
        == .failure(.duplicateExerciseID))
    let twin = Exercise(id: exerciseID(3), name: exercises[0].name, bodyPart: .other)
    #expect(
      TrainingLog.make(exercises: exercises + [twin], sets: sets, memos: [:])
        == .failure(.duplicateExerciseName))
    #expect(
      TrainingLog.make(exercises: exercises, sets: sets + sets, memos: [:])
        == .failure(.duplicateSetID))
    #expect(
      TrainingLog.make(exercises: [exercises[1]], sets: sets, memos: [:])
        == .failure(.unknownExercise))
  }
}

@Suite struct TrainingLogPropertyTests {
  private static let names = ["ベンチプレス", "スクワット", "デッドリフト", "懸垂", "", " ", "ベンチ\nプレス"]

  private static func command(
    for log: TrainingLog, using generator: inout SeededGenerator
  ) -> Command {
    let exercise = ExerciseID(uuid(UInt32.random(in: 1...6, using: &generator)))
    let set = SetID(uuid(UInt32.random(in: 1...40, using: &generator)))
    let name = names[Int.random(in: 0..<names.count, using: &generator)]
    let part = BodyPart.allCases[Int.random(in: 0..<BodyPart.allCases.count, using: &generator)]
    let day =
      LocalDay.earliest.adding(days: Int.random(in: 46_000...46_005, using: &generator))
      ?? .earliest
    let weight = Weight(hundredths: Int.random(in: 0...3, using: &generator) * 2500) ?? .bodyweight
    let count = Reps(Int.random(in: 1...12, using: &generator)) ?? Reps.one
    switch Int.random(in: 0..<10, using: &generator) {
    case 0: return .addExercise(id: exercise, name: name, bodyPart: part)
    case 1: return .editExercise(id: exercise, name: name, bodyPart: part)
    case 2: return .setExerciseArchived(id: exercise, isArchived: Bool.random(using: &generator))
    case 3: return .deleteExercise(id: exercise)
    case 4, 5, 6:
      return .logSet(id: set, exerciseID: exercise, day: day, weight: weight, reps: count)
    case 7: return .editSet(id: set, weight: weight, reps: count)
    case 8: return .deleteSet(id: set)
    default: return .writeMemo(day: day, text: name)
    }
  }

  @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
  func everyCommandSequenceKeepsTheLogWholeAndItsChangesComplete(seed: UInt64) {
    var generator = SeededGenerator(seed: seed)
    var log = TrainingLog.empty
    var rows = RowModel()
    var accepted = 0
    for step in 0..<600 {
      let command = Self.command(for: log, using: &generator)
      guard case .success(let transition) = log.apply(command) else { continue }
      accepted += 1
      log = transition.log
      rows.store(transition.changes)
      let rebuilt = TrainingLog.make(exercises: log.exercises, sets: log.sets, memos: log.memos)
      if rebuilt != .success(log) || rows != RowModel(log) {
        Issue.record("Seed \(seed) broke the log at step \(step) with \(command)")
        return
      }
    }
    #expect(accepted > 100)
  }
}
