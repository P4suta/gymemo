import Foundation
import Testing

@testable import GymemoKit

@Suite struct SQLiteDatabaseTests {
  @Test func storesAndReadsTextAndIntegers() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("values.sqlite"))
    try database.execute("CREATE TABLE item (name TEXT NOT NULL, amount INTEGER)")
    let stored: [(String, Int64?)] = [
      ("", nil), ("ベンチプレス", 6250), ("a'b\"c; DROP TABLE item", .min), ("カ\u{3099}", .max),
    ]
    for (name, amount) in stored {
      try database.execute(
        "INSERT INTO item (name, amount) VALUES (?, ?)",
        [.text(name), amount.map(SQLValue.integer) ?? .null])
    }
    let rows = try database.query("SELECT name, amount FROM item ORDER BY rowid") {
      row throws(StoreFailure) in
      (try row.text(0), row.optionalInteger(1))
    }
    #expect(
      rows.map(\.0.unicodeScalars).map(Array.init) == stored.map(\.0.unicodeScalars).map(Array.init)
    )
    #expect(rows.map(\.1) == stored.map(\.1))
  }

  @Test func insertsManyRowsThroughOnePreparedStatement() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("batch.sqlite"))
    try database.execute("CREATE TABLE item (name TEXT NOT NULL, amount INTEGER NOT NULL)")
    let rows = (0..<500).map { [SQLValue.text("row \($0)"), .integer(Int64($0))] }
    try database.batch("INSERT INTO item (name, amount) VALUES (?, ?)", rows)
    #expect(
      try database.query("SELECT count(*), sum(amount) FROM item") { row in
        [row.integer(0), row.integer(1)]
      } == [[500, 124_750]])
    #expect(throws: StoreFailure.parameterCount) {
      try database.batch("INSERT INTO item (name, amount) VALUES (?, ?)", [[.text("short")]])
    }
  }

  @Test func keepsCommittedRowsAfterReopening() throws {
    let directory = try TemporaryDirectory()
    let file = directory.file("reopen.sqlite")
    do {
      let database = try SQLiteDatabase(url: file)
      try database.execute("CREATE TABLE item (name TEXT NOT NULL)")
      try database.transaction { () throws(StoreFailure) in
        try database.execute("INSERT INTO item (name) VALUES (?)", [.text("kept")])
      }
      try database.close()
    }
    let reopened = try SQLiteDatabase(url: file)
    #expect(
      try reopened.query("SELECT name FROM item") { row throws(StoreFailure) in try row.text(0) }
        == ["kept"])
  }

  @Test func rollsBackEveryChangeOfAFailedTransaction() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("rollback.sqlite"))
    try database.execute("CREATE TABLE item (name TEXT NOT NULL UNIQUE)")
    try database.execute("INSERT INTO item (name) VALUES (?)", [.text("first")])
    #expect(throws: StoreFailure.corruptRow(table: "planted")) {
      try database.transaction { () throws(StoreFailure) in
        try database.execute("INSERT INTO item (name) VALUES (?)", [.text("second")])
        throw StoreFailure.corruptRow(table: "planted")
      }
    }
    #expect(throws: StoreFailure.self) {
      try database.transaction { () throws(StoreFailure) in
        try database.execute("INSERT INTO item (name) VALUES (?)", [.text("third")])
        try database.execute("INSERT INTO item (name) VALUES (?)", [.text("first")])
      }
    }
    #expect(
      try database.query("SELECT name FROM item") { row throws(StoreFailure) in try row.text(0) }
        == ["first"])
    try database.transaction { () throws(StoreFailure) in
      try database.execute("INSERT INTO item (name) VALUES (?)", [.text("fourth")])
    }
    #expect(try database.query("SELECT count(*) FROM item") { row in row.integer(0) } == [2])
  }

  @Test func reportsTheSQLiteResultCode() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("errors.sqlite"))
    #expect {
      try database.execute("SELEC 1")
    } throws: { error in
      guard case .sqlite(let code, let message) = error as? StoreFailure else { return false }
      return code == 1 && !message.isEmpty
    }
    try database.execute("CREATE TABLE item (name TEXT NOT NULL)")
    #expect(throws: StoreFailure.parameterCount) {
      try database.execute("INSERT INTO item (name) VALUES (?)", [])
    }
    #expect {
      try SQLiteDatabase(url: directory.file("missing/unopenable.sqlite"))
    } throws: { error in
      if case .sqlite = error as? StoreFailure { true } else { false }
    }
  }

  @Test func enforcesForeignKeys() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("keys.sqlite"))
    try database.execute("CREATE TABLE parent (id TEXT PRIMARY KEY NOT NULL)")
    try database.execute("CREATE TABLE child (parent TEXT NOT NULL REFERENCES parent (id))")
    #expect(throws: StoreFailure.self) {
      try database.execute("INSERT INTO child (parent) VALUES (?)", [.text("absent")])
    }
  }

  @Test func readsTextUpToItsByteLimitAndRefusesLongerText() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("limit.sqlite"))
    // The three characters take nine bytes.
    let nineBytes = "ベンチ"
    #expect(
      try database.query("SELECT ?", [.text(nineBytes)]) { row throws(StoreFailure) in
        try row.text(0, maximumBytes: 9)
      } == [nineBytes])
    #expect(throws: StoreFailure.textTooLarge) {
      try database.query("SELECT ?", [.text(nineBytes)]) { row throws(StoreFailure) in
        try row.text(0, maximumBytes: 8)
      }
    }
    let mebibyte = 1_048_576
    let longest = String(repeating: "a", count: mebibyte)
    #expect(
      try database.query("SELECT ?", [.text(longest)]) { row throws(StoreFailure) in
        try row.text(0).utf8.count
      } == [mebibyte])
    #expect(throws: StoreFailure.textTooLarge) {
      try database.query("SELECT ?", [.text(longest + "a")]) { row throws(StoreFailure) in
        try row.text(0)
      }
    }
  }

  @Test func bindsEachValueWithItsOwnType() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("types.sqlite"))
    let values: [SQLValue] = [.text(""), .text("a"), .integer(0), .null]
    let types = try values.map { value in
      try database.query("SELECT typeof(?)", [value]) { row throws(StoreFailure) in
        try row.text(0)
      }
    }
    #expect(types == [["text"], ["text"], ["integer"], ["null"]])
    try database.execute("CREATE TABLE item (name TEXT, amount INTEGER)")
    try database.batch(
      "INSERT INTO item (name, amount) VALUES (?, ?)", [[.text(""), .null], [.null, .integer(0)]])
    #expect(
      try database.query("SELECT typeof(name) || ' ' || typeof(amount) FROM item ORDER BY rowid") {
        row throws(StoreFailure) in try row.text(0)
      } == ["text null", "null integer"])
  }

  @Test func setsABusyTimeoutOfFiveSeconds() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("busy.sqlite"))
    #expect(try database.query("PRAGMA busy_timeout") { row in row.integer(0) } == [5000])
  }

  @Test func reportsWhyAFileDoesNotOpen() throws {
    let directory = try TemporaryDirectory()
    #expect(throws: StoreFailure.sqlite(code: 14, message: "unable to open database file")) {
      try SQLiteDatabase(url: directory.file("missing/unopenable.sqlite"))
    }
  }

  @Test func aClosedConnectionRefusesEveryStatement() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("closed.sqlite"))
    try database.execute("CREATE TABLE item (name TEXT NOT NULL)")
    try database.close()
    let refusedQuery = #expect(throws: StoreFailure.self) {
      try database.query("SELECT count(*) FROM item") { row in row.integer(0) }
    }
    #expect(refusedQuery?.code == 21)
    let refusedBatch = #expect(throws: StoreFailure.self) {
      try database.batch("INSERT INTO item (name) VALUES (?)", [[.text("late")]])
    }
    #expect(refusedBatch?.code == 21)
    try database.close()
    let reopened = try SQLiteDatabase(url: directory.file("closed.sqlite"))
    #expect(try reopened.query("SELECT count(*) FROM item") { row in row.integer(0) } == [0])
  }

  @Test func refusesToCloseWhileAStatementStillRuns() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("running.sqlite"))
    let refusal = #expect(throws: StoreFailure.self) {
      try database.query("SELECT 1") { _ throws(StoreFailure) in try database.close() }
    }
    #expect(refusal?.code == 5)
    #expect(try database.query("SELECT 2") { row in row.integer(0) } == [2])
    try database.close()
  }

  /// One way in which a query or a batch ends.
  enum Ending: CaseIterable {
    case queryReturns, queryIsNotSQL, queryLacksAValue, queryBreaksAConstraint, queryRefusesARow
    case batchReturns, batchIsNotSQL, batchLacksAValue, batchBreaksAConstraint
  }

  @Test(arguments: Ending.allCases)
  func releasesItsStatementHoweverTheWorkEnds(ending: Ending) throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("release.sqlite"))
    try database.execute("CREATE TABLE item (name TEXT NOT NULL UNIQUE)")
    let insert = "INSERT INTO item (name) VALUES (?)"
    try database.execute(insert, [.text("taken")])
    let taken = StoreFailure.sqlite(code: 19, message: "UNIQUE constraint failed: item.name")
    switch ending {
    case .queryReturns:
      #expect(
        try database.query("SELECT name FROM item") { row throws(StoreFailure) in
          try row.text(0)
        } == ["taken"])
    case .queryIsNotSQL:
      let refusal = #expect(throws: StoreFailure.self) { try database.execute("SELEC 1") }
      #expect(refusal?.code == 1)
    case .batchIsNotSQL:
      let refusal = #expect(throws: StoreFailure.self) { try database.batch("INSER 1", [[]]) }
      #expect(refusal?.code == 1)
    case .queryLacksAValue:
      #expect(throws: StoreFailure.parameterCount) { try database.execute(insert) }
    case .queryBreaksAConstraint:
      #expect(throws: taken) { try database.execute(insert, [.text("taken")]) }
    case .queryRefusesARow:
      #expect(throws: StoreFailure.corruptRow(table: "planted")) {
        try database.query("SELECT name FROM item") { _ throws(StoreFailure) -> String in
          throw .corruptRow(table: "planted")
        }
      }
    case .batchReturns:
      try database.batch(insert, [[.text("first")], [.text("second")]])
    case .batchLacksAValue:
      #expect(throws: StoreFailure.parameterCount) {
        try database.batch(insert, [[.text("first")], []])
      }
    case .batchBreaksAConstraint:
      #expect(throws: taken) { try database.batch(insert, [[.text("first")], [.text("taken")]]) }
    }
    try database.close()
  }

  @Test func aBatchRunsAStatementThatReturnsRowsToItsEnd() throws {
    let directory = try TemporaryDirectory()
    let database = try SQLiteDatabase(url: directory.file("returning.sqlite"))
    try database.execute("CREATE TABLE item (name TEXT NOT NULL)")
    try database.batch(
      "INSERT INTO item (name) VALUES (?) RETURNING name", [[.text("first")], [.text("second")]])
    try database.batch(
      "UPDATE item SET name = name || ? RETURNING name", [[.text("!")], [.text("?")]])
    #expect(
      try database.query("SELECT name FROM item ORDER BY rowid") { row throws(StoreFailure) in
        try row.text(0)
      } == ["first!?", "second!?"])
    try database.close()
  }
}
