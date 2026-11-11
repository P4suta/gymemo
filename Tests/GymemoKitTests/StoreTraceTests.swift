import Foundation
import GymemoCore
import GymemoTestSupport
import OSLog
import Testing

@testable import GymemoKit

/// Two places in the unified log between which a test reads the lines that its own thread made the store write.
/// A synchronous test stays on one thread, so no other test writes on that thread between the two places.
private struct StoreLogMark {
  private let opening: String
  private let closing: String
  private let thread: UInt64

  init() {
    let text = "mark \(UUID().uuidString)"
    var thread: UInt64 = 0
    pthread_threadid_np(nil, &thread)
    opening = "\(text) opens"
    closing = "\(text) closes"
    self.thread = thread
    Self.write(opening)
  }

  /// Writes `text` at the level of the store's failure lines, so the log keeps it the same way.
  private static func write(_ text: String) {
    Logger(subsystem: "com.p4suta.gymemo.tests", category: "mark").error(
      "\(text, privacy: .public)")
  }

  /// The lines that the store wrote on this thread since the mark, or `nil` when the log never showed both marks.
  /// The log shows an entry a moment after its call and keeps one thread's entries in order.
  /// This closes the mark on the same thread and reads again until the closing mark is there or `patience` runs out.
  /// The closing mark shows up with or without the store's lines, so only a stalled log waits out `patience`.
  /// A short rest between two readings keeps the load on the log service low when many test processes read at once.
  func storeLines(patience: Duration = .seconds(20)) throws -> [String]? {
    Self.write(closing)
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", "com.p4suta.gymemo")
    let deadline = ContinuousClock.now + patience
    while true {
      var lines: [String]?
      for case let entry as OSLogEntryLog in try store.getEntries(matching: predicate)
      where entry.threadIdentifier == thread {
        if entry.composedMessage == opening {
          lines = []
        } else if entry.composedMessage == closing, let lines {
          return lines
        } else if entry.subsystem == "com.p4suta.gymemo", entry.category == "store" {
          lines?.append(entry.composedMessage)
        }
      }
      guard ContinuousClock.now < deadline else { return nil }
      Thread.sleep(forTimeInterval: 0.02)
    }
  }
}

@Suite struct StoreTraceTests {
  @Test func writesTheOperationAndTheCodeOfEachFailureToTheLog() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("log.sqlite")
    let stray = LoggedSet(
      id: setID(1), exerciseID: exerciseID(404), day: try #require(LocalDay(iso: "2026-11-09")),
      weight: .bodyweight, reps: .one)
    let mark = StoreLogMark()
    #expect(throws: StoreFailure.self) {
      try TrainingLogStore(url: directory.file("absent/log.sqlite"), starter: .starter)
    }
    let store = try TrainingLogStore(url: file, starter: .starter)
    try store.apply([.removeSet(stray.id)])
    #expect(throws: StoreFailure.self) { try store.apply([.putSet(stray)]) }
    #expect(try store.load() == .starter)
    let database = try SQLiteDatabase(url: file)
    try database.execute("UPDATE exercise SET body_part = 'wings' WHERE position = 0")
    try database.close()
    #expect(throws: StoreFailure.corruptRow(table: "exercise")) { try store.receive(stray) }
    #expect(throws: StoreFailure.corruptRow(table: "exercise")) { try store.load() }
    let lines = try #require(try mark.storeLines(), "The log never showed both marks.")
    #expect(
      lines == [
        "store.open failed code=14", "store.apply failed code=19", "store.apply failed code=-5",
        "store.load failed code=-5",
      ])
  }
}
