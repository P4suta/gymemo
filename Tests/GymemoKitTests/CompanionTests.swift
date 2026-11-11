import Foundation
import GymemoCore
import GymemoTestSupport
import Testing

@testable import GymemoKit

@MainActor
@Suite struct CompanionTests {
  private struct JournalRecord: Encodable {
    let message: Data
    let name: String?
  }

  private struct JournalFile: Encodable {
    let version = 1
    let catalog: Data
    let entries: [JournalRecord]
  }

  private func writeJournal(_ entries: [CompanionQueuedSet], to file: URL) throws {
    let records = try entries.map { entry in
      let message: CompanionMessage =
        entry.outcome.map {
          .receipt(CompanionReceipt(set: entry.set, outcome: $0))
        } ?? .entry(entry.set)
      return JournalRecord(
        message: try CompanionCodec.encode(message), name: entry.exerciseName?.text)
    }
    let snapshot = JournalFile(
      catalog: try CompanionCodec.encode(.catalog(CompanionCatalog(log: .empty))), entries: records)
    try JSONEncoder().encode(snapshot).write(to: file)
  }

  private func entry(_ number: UInt32 = 1, exercise: ExerciseID? = nil) throws -> LoggedSet {
    LoggedSet(
      id: setID(number), exerciseID: exercise ?? TrainingLog.starter.exercises[0].id,
      day: try #require(LocalDay(iso: "2026-11-09")),
      weight: try #require(Weight(hundredths: 6000)), reps: try #require(Reps(8)))
  }

  @Test func thePhoneCommitsAnEntryOnceAndDoesNotResurrectADeletedSet() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("phone.sqlite")
    var store = try TrainingLogStore(url: file, starter: .starter)
    let set = try entry()
    let first = try store.receive(set)
    #expect(first.receipt == CompanionReceipt(set: set, outcome: .saved))
    #expect(first.log.sets == [set])
    #expect(try store.receive(set).log == first.log)
    try store.apply([.removeSet(set.id)])
    store = try TrainingLogStore(url: file, starter: .empty)
    #expect(try store.receive(set).receipt.outcome == .saved)
    #expect(try store.load().sets.isEmpty)
  }

  @Test func conflictingIdentifiersAndUnknownExercisesNeverReplacePhoneRecords() throws {
    let directory = try TemporaryDirectory()
    let store = try TrainingLogStore(url: directory.file("phone.sqlite"), starter: .starter)
    let set = try entry()
    _ = try store.receive(set)
    var changed = set
    changed.reps = .one
    #expect(try store.receive(changed).receipt.outcome == .identifierConflict)
    #expect(try store.load().sets == [set])
    let unknown = try entry(2, exercise: exerciseID(999))
    #expect(try store.receive(unknown).receipt.outcome == .unknownExercise)
    #expect(try store.load().sets == [set])
  }

  @Test func aFailedCommitLeavesNeitherTheSetNorAnAcknowledgment() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("phone.sqlite")
    let store = try TrainingLogStore(url: file, starter: .starter)
    let connection = try SQLiteDatabase(url: file)
    try connection.execute(
      """
      CREATE TRIGGER refuse_receipt BEFORE INSERT ON companion_receipt
      BEGIN SELECT RAISE(ABORT, 'refused'); END
      """)
    #expect(throws: StoreFailure.self) { try store.receive(try entry()) }
    #expect(try store.load() == .starter)
    try connection.execute("DROP TRIGGER refuse_receipt")
    #expect(try store.receive(try entry()).log.sets.count == 1)
  }

  @Test func anExistingSetCanBeAcknowledgedWithoutAddingItAgain() throws {
    let directory = try TemporaryDirectory()
    let store = try TrainingLogStore(url: directory.file("phone.sqlite"), starter: .starter)
    let set = try entry()
    try store.apply([.putSet(set)])
    #expect(try store.receive(set).receipt.outcome == .saved)
    var changed = set
    changed.reps = .one
    #expect(try store.receive(changed).receipt.outcome == .identifierConflict)
    #expect(try store.load().sets == [set])
    try store.apply([.replaceAll(.starter)])
    #expect(try store.receive(set).log.sets.isEmpty)
  }

  @Test func theSchemaMigrationPreservesExistingRecords() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("phone.sqlite")
    let set = try entry()
    do {
      let store = try TrainingLogStore(url: file, starter: .starter)
      try store.apply([.putSet(set)])
    }
    do {
      let connection = try SQLiteDatabase(url: file)
      try connection.execute("DROP TABLE companion_receipt")
      try connection.execute("PRAGMA user_version = 1")
    }
    let migrated = try TrainingLogStore(url: file, starter: .empty)
    #expect(try migrated.load().sets == [set])
    #expect(try migrated.receive(set).receipt.outcome == .saved)
    #expect(try TrainingLogStore(url: file, starter: .empty).load().sets == [set])
  }

  @Test func aWatchQueueSurvivesRelaunchAndIgnoresMismatchedAndStaleReceipts() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("watch.json")
    let set = try entry()
    let first = try CompanionJournal(url: file)
    try first.enqueue(set)
    let reopened = try CompanionJournal(url: file)
    #expect(reopened.entries == [CompanionQueuedSet(set: set, outcome: nil)])
    var changed = set
    changed.reps = .one
    try reopened.acknowledge(CompanionReceipt(set: changed, outcome: .saved))
    #expect(reopened.entries[0].outcome == nil)
    try reopened.acknowledge(CompanionReceipt(set: set, outcome: .saved))
    try reopened.acknowledge(CompanionReceipt(set: set, outcome: .unknownExercise))
    #expect(try CompanionJournal(url: file).entries[0].outcome == .saved)
    #expect(throws: CompanionFailure.duplicateIdentifier) { try reopened.enqueue(set) }
  }

  @Test func theWireRoundTripsValidatedDataAndRefusesUnknownOrMalformedPayloads() throws {
    let set = try entry()
    let messages: [CompanionMessage] = [
      .entry(set), .receipt(CompanionReceipt(set: set, outcome: .saved)),
      .catalog(CompanionCatalog(log: .starter)),
    ]
    for message in messages {
      #expect(try CompanionCodec.decode(CompanionCodec.encode(message)) == message)
    }
    for invalid in [
      "{}", "{\"version\":2,\"kind\":\"entry\"}",
      "{\"version\":1,\"kind\":\"entry\",\"entry\":{\"id\":\"bad\"}}",
    ] {
      #expect(throws: CompanionFailure.self) { try CompanionCodec.decode(Data(invalid.utf8)) }
    }
    #expect(throws: CompanionFailure.tooLarge) {
      try CompanionCodec.decode(Data(repeating: 0, count: CompanionCodec.maximumBytes + 1))
    }
  }

  @Test func theWireAcceptsTheExactByteAndCatalogLimitsAndRefusesOneMoreByte() throws {
    func message(marks: Int, suffix: String) throws -> CompanionMessage {
      let exercises = try (0..<CompanionCatalog.maximumExercises).map { index in
        let padding = index == 0 ? String(repeating: "\u{0301}", count: marks) + suffix : ""
        let name = try ExerciseName.parse("Exercise \(index)" + padding).get()
        return CompanionExercise(
          exercise: Exercise(id: exerciseID(UInt32(index)), name: name, bodyPart: .other),
          suggestion: nil)
      }
      return .catalog(try #require(CompanionCatalog(exercises: exercises)))
    }
    let base = try CompanionCodec.encode(message(marks: 0, suffix: ""))
    let padding = CompanionCodec.maximumBytes - base.count
    let suffix = padding.isMultiple(of: 2) ? "" : "a"
    let maximum = try message(marks: padding / 2, suffix: suffix)
    let data = try CompanionCodec.encode(maximum)
    #expect(data.count == CompanionCodec.maximumBytes)
    #expect(try CompanionCodec.decode(data) == maximum)
    #expect(throws: CompanionFailure.tooLarge) {
      try CompanionCodec.encode(message(marks: padding / 2, suffix: suffix + "b"))
    }
    var oversized = data
    oversized.append(0x20)
    #expect(throws: CompanionFailure.tooLarge) { try CompanionCodec.decode(oversized) }
  }

  @Test func aJournalAcceptsTheExactFileLimitAndPreservesAnOversizedFile() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("watch.json")
    let entries = [CompanionQueuedSet(set: try entry(), outcome: nil)]
    try writeJournal(entries, to: file)
    var data = try Data(contentsOf: file)
    data.append(Data(repeating: 0x20, count: 2_000_000 - data.count))
    try data.write(to: file)
    #expect(try CompanionJournal(url: file).entries == entries)
    data.append(0x20)
    try data.write(to: file)
    #expect(throws: CompanionFailure.malformed) { try CompanionJournal(url: file) }
    #expect(try Data(contentsOf: file) == data)
  }

  @Test func aFailedJournalReplacementKeepsThePreviousInMemoryState() throws {
    let directory = try TemporaryDirectory()
    let journal = try CompanionJournal(url: directory.file("absent/watch.json"))
    #expect(throws: CompanionFailure.self) { try journal.enqueue(try entry()) }
    #expect(journal.entries.isEmpty)
    #expect(journal.catalog == CompanionCatalog(log: .empty))
  }

  @Test func catalogChangesPersistAndRefusedEntriesCanBeRetried() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("watch.json")
    let journal = try CompanionJournal(url: file)
    let set = try entry()
    let catalog = CompanionCatalog(log: .starter)
    try journal.update(catalog)
    try journal.enqueue(set)
    #expect(journal.entries[0].exerciseName == catalog.exercises[0].exercise.name)
    try journal.acknowledge(CompanionReceipt(set: set, outcome: .full))
    #expect(journal.entries[0].outcome == .full)
    try journal.retry(set.id)
    #expect(journal.entries[0].outcome == nil)
    try journal.acknowledge(CompanionReceipt(set: set, outcome: .saved))
    try journal.retry(set.id)
    try journal.retry(setID(999))
    try journal.acknowledge(CompanionReceipt(set: try entry(999), outcome: .saved))
    let reopened = try CompanionJournal(url: file)
    #expect(reopened.catalog == catalog)
    #expect(reopened.entries[0].exerciseName == catalog.exercises[0].exercise.name)
    #expect(reopened.entries[0].outcome == .saved)
  }

  @Test func malformedJournalFilesDoNotSilentlyDiscardPendingRecords() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("watch.json")
    for invalid in ["{}", "{\"version\":99}", "not json"] {
      try Data(invalid.utf8).write(to: file)
      #expect(throws: CompanionFailure.self) { try CompanionJournal(url: file) }
      #expect(try String(contentsOf: file, encoding: .utf8) == invalid)
    }
  }

  @Test func theWatchQueueIsBoundedWithoutDroppingUnacknowledgedEntries() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("watch.json")
    let entries = try (0..<UInt32(CompanionJournal.maximumEntries)).map {
      CompanionQueuedSet(set: try entry($0), outcome: nil)
    }
    try writeJournal(entries, to: file)
    let journal = try CompanionJournal(url: file)
    #expect(throws: CompanionFailure.queueFull) {
      try journal.enqueue(try entry(UInt32(CompanionJournal.maximumEntries)))
    }
    #expect(try CompanionJournal(url: file).entries == journal.entries)
    let acknowledged = entries.enumerated().map { index, entry in
      CompanionQueuedSet(set: entry.set, outcome: index < 150 ? .saved : nil)
    }
    try writeJournal(acknowledged, to: file)
    let withSaved = try CompanionJournal(url: file)
    try withSaved.enqueue(try entry(10_000))
    #expect(withSaved.entries.filter { $0.outcome == nil }.count == 851)
    #expect(withSaved.entries.filter { $0.outcome == .saved }.count == 99)
  }

  @Test func malformedWireFieldsAreRejectedBeforeTheyBecomeDomainValues() throws {
    let base = String(decoding: try CompanionCodec.encode(.entry(try entry())), as: UTF8.self)
    for (original, replacement) in [
      ("\"version\":1", "\"version\":2"),
      ("\"hundredths\":6000", "\"hundredths\":-1"),
      ("\"reps\":8", "\"reps\":0"),
      ("2026-11-09", "2026-02-30"),
      ("\"kind\":\"entry\"", "\"kind\":\"unknown\""),
      ("\"version\":1", "\"version\":1,\"outcome\":\"saved\""),
      ("\"version\":1", "\"version\":1,\"exercises\":[]"),
    ] {
      let invalid = base.replacingOccurrences(of: original, with: replacement)
      #expect(invalid != base)
      #expect(throws: CompanionFailure.self) { try CompanionCodec.decode(Data(invalid.utf8)) }
    }
  }
}
