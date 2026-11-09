import Foundation
import GymemoCore
import GymemoTestSupport
import Testing

/// The case of a command without its values, which an exhaustive switch names, so that a new case of `Command` needs pairs of its own.
private enum CommandKind {
  case addExercise, editExercise, setExerciseArchived, deleteExercise, logSet, editSet, deleteSet
  case writeMemo, replaceAll

  init(_ command: Command) {
    switch command {
    case .addExercise: self = .addExercise
    case .editExercise: self = .editExercise
    case .setExerciseArchived: self = .setExerciseArchived
    case .deleteExercise: self = .deleteExercise
    case .logSet: self = .logSet
    case .editSet: self = .editSet
    case .deleteSet: self = .deleteSet
    case .writeMemo: self = .writeMemo
    case .replaceAll: self = .replaceAll
    }
  }
}

/// The case of a change without its values.
private enum ChangeKind {
  case putExercise, removeExercise, putSet, removeSet, putMemo, removeMemo, replaceAll

  init(_ change: Change) {
    switch change {
    case .putExercise: self = .putExercise
    case .removeExercise: self = .removeExercise
    case .putSet: self = .putSet
    case .removeSet: self = .removeSet
    case .putMemo: self = .putMemo
    case .removeMemo: self = .removeMemo
    case .replaceAll: self = .replaceAll
    }
  }
}

/// A case of `Command` with a refusal that `TrainingLog.apply` returned for it.
private struct RefusalPair: Equatable {
  let command: CommandKind
  let refusal: Refusal

  init(_ command: CommandKind, _ refusal: Refusal) {
    self.command = command
    self.refusal = refusal
  }
}

/// A case of `Command` with the cases of the changes that `TrainingLog.apply` returned for it.
private struct ChangePair: Equatable {
  let command: CommandKind
  let changes: [ChangeKind]

  init(_ command: CommandKind, _ changes: [ChangeKind]) {
    self.command = command
    self.changes = changes
  }
}

@Suite struct LeanVectorsTests {
  /// Every step that a command gives, as the Lean files write it.
  private static let steps = [
    ".refused (.exerciseName .empty)", ".refused (.exerciseName .tooLong)",
    ".refused (.exerciseName .controlCharacter)", ".refused .duplicateExerciseName",
    ".refused .duplicateIdentifier", ".refused .unknownExercise", ".refused .exerciseHasSets",
    ".refused .unknownSet", ".refused (.memo .tooLong)", ".refused (.memo .controlCharacter)",
    ".refused .full", ".changed []", ".changed [.putExercise ", ".changed [.removeExercise ",
    ".changed [.putSet ", ".changed [.removeSet ", ".changed [.putMemo ", ".changed [.removeMemo ",
    ".changed [.replaceAll ",
  ]

  /// Every refusal that `TrainingLog.make` gives.
  private static let refusals: [IntegrityRefusal] = [
    .duplicateExerciseID, .duplicateExerciseName, .duplicateSetID, .unknownExercise,
    .tooManyExercises, .tooManySets,
  ]

  /// Every refusal that `TrainingLog.apply` can return for each case of `Command`, as `Command.swift` and the parsers of `Exercise.swift` and `LoggedSet.swift` return them.
  /// Only the limit sequences reach `.full` of `addExercise` and `.full` of `logSet`.
  /// `replaceExercise` refuses a repeated name, but an archived exercise keeps its name, and the names of a log differ, so `setExerciseArchived` never returns `.duplicateExerciseName`.
  private static let refusalsByCommand: [(CommandKind, [Refusal])] = [
    (
      .addExercise,
      [
        .exerciseName(.empty), .exerciseName(.tooLong), .exerciseName(.controlCharacter),
        .duplicateIdentifier, .duplicateExerciseName, .full,
      ]
    ),
    (
      .editExercise,
      [
        .exerciseName(.empty), .exerciseName(.tooLong), .exerciseName(.controlCharacter),
        .unknownExercise, .duplicateExerciseName,
      ]
    ),
    (.setExerciseArchived, [.unknownExercise]),
    (.deleteExercise, [.unknownExercise, .exerciseHasSets]),
    (.logSet, [.unknownExercise, .duplicateIdentifier, .full]),
    (.editSet, [.unknownSet]),
    (.deleteSet, [.unknownSet]),
    (.writeMemo, [.memo(.tooLong), .memo(.controlCharacter)]),
    (.replaceAll, []),
  ]

  /// Every list of changes that `TrainingLog.apply` can return for each case of `Command`, where an empty list leaves the log unchanged.
  private static let changesByCommand: [(CommandKind, [[ChangeKind]])] = [
    (.addExercise, [[.putExercise]]),
    (.editExercise, [[], [.putExercise]]),
    (.setExerciseArchived, [[], [.putExercise]]),
    (.deleteExercise, [[.removeExercise]]),
    (.logSet, [[.putSet]]),
    (.editSet, [[], [.putSet]]),
    (.deleteSet, [[.removeSet]]),
    (.writeMemo, [[], [.putMemo], [.removeMemo]]),
    (.replaceAll, [[.replaceAll]]),
  ]

  /// The log file, which both log tests read, because its set limit builds logs of a million sets.
  private static let logFile: Result<LeanVectors.LogFile, any Error> = Result {
    try LeanVectors.log()
  }

  /// Compares a rendered Lean file with the committed one, after writing it when `just gen` asks.
  private func expectCommitted(_ name: String, _ rendering: String) throws {
    let path = "specs/lean/Gymemo/\(name).lean"
    let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: path)
    if ProcessInfo.processInfo.environment["GYMEMO_WRITE_VECTORS"] == "1" {
      try Data(rendering.utf8).write(to: file, options: .atomic)
    }
    let rendered = Array(rendering.utf8)
    let committed = (try? Array(Data(contentsOf: file))) ?? []
    guard committed != rendered else { return }
    let shared = zip(committed, rendered).prefix { $0 == $1 }
    let line = shared.count { $0.0 == UInt8(ascii: "\n") } + 1
    Issue.record(
      """
      \(path) differs from the results of the Swift code from line \(line), \
      so run `mise x -- just gen`, then check that `lake build --wfail` in specs/lean passes
      """)
  }

  @Test func theLogVectorsHoldTheResultsOfTheSwiftCode() throws {
    let file = try Self.logFile.get()
    for (number, walk) in file.walks.enumerated() {
      #expect(walk.broken.isEmpty, "Sequence \(number) broke the log at \(walk.broken)")
    }
    for step in Self.steps {
      #expect(file.text.contains("\n  \(step)"), "No sequence gives \(step)")
    }
    let refusesAFullSet = file.walks.contains { walk in
      zip(walk.commands, walk.results).contains { command, result in
        guard case .logSet = command else { return false }
        return result == .failure(.full)
      }
    }
    #expect(refusesAFullSet, "No sequence refuses a set as .full")
    let made = file.rows.map(\.made)
    for refusal in Self.refusals {
      #expect(made.contains(.failure(refusal)), "No rows give \(refusal)")
    }
    let beyondBothLimits = file.rows.contains { rows in
      rows.exercises.count > TrainingLog.maximumExercises
        && rows.sets.count > TrainingLog.maximumSets
    }
    #expect(beyondBothLimits, "No rows pass both limits")
    let logs = file.rows.compactMap { rows in (try? rows.made.get()).map { (rows, $0) } }
    #expect(!logs.isEmpty, "No rows form a log")
    for (rows, log) in logs {
      #expect(log.exercises == rows.exercises && log.sets == rows.sets && log.memos == rows.memos)
    }
    try expectCommitted("LogVectors", file.text)
  }

  /// Lean's kernel checks only the results that some sequence gives.
  /// A case of `Command` that never meets one of its refusals or changes leaves the model's branch for it unchecked.
  @Test func theSequencesGiveEachRefusalAndEachChangeOfEachKindOfCommand() throws {
    let file = try Self.logFile.get()
    var refusals: [RefusalPair] = []
    var changes: [ChangePair] = []
    for walk in file.walks {
      for (command, result) in zip(walk.commands, walk.results) {
        switch result {
        case .failure(let refusal):
          let pair = RefusalPair(CommandKind(command), refusal)
          if !refusals.contains(pair) { refusals.append(pair) }
        case .success(let transition):
          let pair = ChangePair(CommandKind(command), transition.changes.map(ChangeKind.init))
          if !changes.contains(pair) { changes.append(pair) }
        }
      }
    }
    let expectedRefusals = Self.refusalsByCommand.flatMap { command, refusals in
      refusals.map { RefusalPair(command, $0) }
    }
    // Each issue names one pair, so that a failure doesn't print every pair that the sequences gave.
    for pair in expectedRefusals where !refusals.contains(pair) {
      Issue.record("No sequence refuses \(pair.command) as \(pair.refusal)")
    }
    for pair in refusals where !expectedRefusals.contains(pair) {
      Issue.record("\(pair.command) returned \(pair.refusal), which the expected pairs lack")
    }
    let expectedChanges = Self.changesByCommand.flatMap { command, lists in
      lists.map { ChangePair(command, $0) }
    }
    for pair in expectedChanges where !changes.contains(pair) {
      Issue.record("No sequence gives \(pair.changes) for \(pair.command)")
    }
    for pair in changes where !expectedChanges.contains(pair) {
      Issue.record("\(pair.command) returned \(pair.changes), which the expected pairs lack")
    }
  }

  @Test func theStrengthVectorsHoldTheResultsOfTheSwiftCode() throws {
    try expectCommitted("StrengthVectors", LeanVectors.strength())
  }

  @Test func theStepperVectorsHoldTheResultsOfTheSwiftCode() throws {
    try expectCommitted("StepperVectors", LeanVectors.stepper())
  }

  /// Two identifiers with the same last four bytes would share a number, so only the identifiers of the test support have one.
  @Test func anIdentifierOfAnotherOriginHasNoNumber() throws {
    let foreign = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
    #expect(throws: VectorFault.foreignIdentifier(foreign)) {
      var terms = LogTerms()
      return try terms.command(.deleteSet(id: SetID(foreign)))
    }
  }

  /// The model orders two days as integers, so it can't tell a day number from one that every rendering shifts alike.
  /// This test holds the rendering to `LocalDay.dayNumber`, which is 0 on 1970-01-01.
  @Test func aDayRendersAsItsNumberOfDaysSince1970() throws {
    var terms = LogTerms()
    let memo = "メモ"
    #expect(
      try terms.command(.writeMemo(day: .earliest, text: memo)).hasPrefix(".writeMemo (-25567) "))
    let epoch = try #require(LocalDay(iso: "1970-01-01"))
    #expect(try terms.command(.writeMemo(day: epoch, text: memo)).hasPrefix(".writeMemo 0 "))
    let later = try #require(LocalDay(iso: "1970-01-02"))
    #expect(try terms.command(.writeMemo(day: later, text: memo)).hasPrefix(".writeMemo 1 "))
  }

  /// The set limit of `TrainingLog.make` holds here and in `Gymemo/LogVectors.lean`, so a change of the limit fails even after `just gen` rewrites the vectors.
  @Test func rowsPassTheSetLimitAndOneMoreSetIsRefused() {
    let set = LoggedSet(
      id: setID(1), exerciseID: exerciseID(1), day: .earliest, weight: .bodyweight, reps: .one)
    let most = Array(repeating: set, count: 1_000_000)
    #expect(TrainingLog.make(exercises: [], sets: most, memos: [:]) == .failure(.unknownExercise))
    #expect(
      TrainingLog.make(exercises: [], sets: most + [set], memos: [:]) == .failure(.tooManySets))
  }

  /// `TrainingLog.make` counts the exercises before the sets here and in `Gymemo/LogVectors.lean`, so a change of that order fails even after `just gen` rewrites the vectors.
  @Test func rowsBeyondBothLimitsAreRefusedForTheirExercises() throws {
    let exercise = Exercise(
      id: exerciseID(1), name: try ExerciseName.parse("ベンチプレス").get(), bodyPart: .chest)
    let set = LoggedSet(
      id: setID(1), exerciseID: exerciseID(1), day: .earliest, weight: .bodyweight, reps: .one)
    let exercises = Array(repeating: exercise, count: TrainingLog.maximumExercises + 1)
    let sets = Array(repeating: set, count: TrainingLog.maximumSets + 1)
    #expect(
      TrainingLog.make(exercises: exercises, sets: sets, memos: [:]) == .failure(.tooManyExercises))
  }
}
