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
}
