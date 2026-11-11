import GymemoCore
import GymemoTestSupport
import Testing

@Suite struct CompanionQueueTests {
  private func set(_ number: UInt32) -> LoggedSet {
    LoggedSet(
      id: setID(number), exerciseID: exerciseID(1), day: .earliest, weight: .bodyweight, reps: .one)
  }

  @Test func queueValidationRefusesDuplicateIdentifiersAndAnOversizedList() throws {
    #expect(CompanionQueue(entries: []) == CompanionQueue())
    let first = CompanionQueuedSet(set: set(1), outcome: nil)
    #expect(CompanionQueue(entries: [first, first]) == nil)
    let oversized = (0...UInt32(CompanionQueue.maximumEntries)).map {
      CompanionQueuedSet(set: set($0), outcome: nil)
    }
    #expect(CompanionQueue(entries: oversized) == nil)
    let full = try #require(CompanionQueue(entries: Array(oversized.dropLast())))
    #expect(full.enqueue(set(10_000), name: nil) == .failure(.full))
    #expect(full.enqueue(set(1), name: nil) == .failure(.duplicateIdentifier))
  }

  @Test func pruningSavedSetsKeepsTheOrderAndEveryPendingSet() throws {
    let entries = (0..<200 as Range<UInt32>).map {
      CompanionQueuedSet(set: set($0), outcome: $0.isMultiple(of: 2) ? .saved : nil)
    }
    let queue = try #require(CompanionQueue(entries: entries))
    let name = try ExerciseName.parse("Bench Press").get()
    let added = try queue.enqueue(set(1000), name: name).get()
    #expect(
      added.entries == Array(entries.dropFirst()) + [
        CompanionQueuedSet(set: set(1000), outcome: nil, exerciseName: name)
      ])
  }

  @Test func receiptsMatchTheWholeEntryAndSavedSetsCannotBecomePendingAgain() throws {
    let name = try ExerciseName.parse("Bench Press").get()
    let queued = try CompanionQueue().enqueue(set(1), name: name).get()
    var other = set(1)
    other.reps = try #require(Reps(2))
    #expect(queued.acknowledging(CompanionReceipt(set: other, outcome: .saved)) == queued)
    #expect(queued.acknowledging(CompanionReceipt(set: set(2), outcome: .saved)) == queued)
    #expect(queued.retrying(setID(2)) == queued)
    let refused = queued.acknowledging(CompanionReceipt(set: set(1), outcome: .full))
    #expect(
      refused.entries == [CompanionQueuedSet(set: set(1), outcome: .full, exerciseName: name)])
    #expect(refused.retrying(setID(1)) == queued)
    let saved = refused.acknowledging(CompanionReceipt(set: set(1), outcome: .saved))
    #expect(saved.entries == [CompanionQueuedSet(set: set(1), outcome: .saved, exerciseName: name)])
    #expect(saved.retrying(setID(1)) == saved)
    #expect(saved.acknowledging(CompanionReceipt(set: set(1), outcome: .full)) == saved)
  }
}
