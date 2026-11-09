import CSQLite
import Foundation

public enum DatabaseFailure: Error, Equatable, Sendable {
  case sqlite(code: Int32, message: String)
  case parameterCount
  case textTooLarge
  case invalidText
}

enum SQLValue: Equatable {
  case text(String)
  case integer(Int64)
  case null
}

/// One row that a statement currently points at, valid only inside the closure that receives it.
struct SQLiteRow {
  fileprivate let statement: OpaquePointer

  func text(_ column: Int32, maximumBytes: Int = 1_048_576) throws -> String {
    let count = Int(sqlite3_column_bytes(statement, column))
    guard count <= maximumBytes else { throw DatabaseFailure.textTooLarge }
    guard let pointer = sqlite3_column_text(statement, column),
      let value = String(bytes: UnsafeBufferPointer(start: pointer, count: count), encoding: .utf8)
    else { throw DatabaseFailure.invalidText }
    return value
  }

  func integer(_ column: Int32) -> Int64 {
    sqlite3_column_int64(statement, column)
  }

  func optionalInteger(_ column: Int32) -> Int64? {
    sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : integer(column)
  }
}

/// One connection that a single owner uses from one thread at a time.
final class SQLiteDatabase {
  private var handle: OpaquePointer?

  init(url: URL) throws {
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
    let status = sqlite3_open_v2(url.path, &handle, flags, nil)
    guard status == SQLITE_OK else {
      let failure = failure(status)
      sqlite3_close_v2(handle)
      handle = nil
      throw failure
    }
    sqlite3_busy_timeout(handle, 5_000)
    // SQLite leaves foreign key enforcement off for each new connection.
    // See https://www.sqlite.org/pragma.html#pragma_foreign_keys.
    try execute("PRAGMA foreign_keys = ON")
  }

  deinit { sqlite3_close_v2(handle) }

  func close() throws {
    guard handle != nil else { return }
    let status = sqlite3_close(handle)
    guard status == SQLITE_OK else { throw failure(status) }
    handle = nil
  }

  func query<Value>(
    _ sql: String, _ values: [SQLValue] = [], row: (SQLiteRow) throws -> Value
  ) throws -> [Value] {
    var prepared: OpaquePointer?
    let status = sqlite3_prepare_v2(handle, sql, -1, &prepared, nil)
    guard status == SQLITE_OK, let statement = prepared else { throw failure(status) }
    defer { sqlite3_finalize(statement) }
    try bind(values, to: statement)
    var rows: [Value] = []
    while true {
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return rows }
      guard step == SQLITE_ROW else { throw failure(step) }
      rows.append(try row(SQLiteRow(statement: statement)))
    }
  }

  func execute(_ sql: String, _ values: [SQLValue] = []) throws {
    _ = try query(sql, values) { _ in () }
  }

  /// Runs `body` so that the database stores all its changes or none.
  /// A failed rollback never hides the error that caused it.
  func transaction<Value>(_ body: () throws -> Value) throws -> Value {
    try execute("BEGIN IMMEDIATE")
    do {
      let value = try body()
      try execute("COMMIT")
      return value
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  private func failure(_ code: Int32) -> DatabaseFailure {
    .sqlite(code: code, message: String(cString: sqlite3_errmsg(handle)))
  }

  private func bind(_ values: [SQLValue], to statement: OpaquePointer) throws {
    guard sqlite3_bind_parameter_count(statement) == values.count else {
      throw DatabaseFailure.parameterCount
    }
    for (index, value) in values.enumerated() {
      let position = Int32(index + 1)
      let status: Int32
      switch value {
      case .text(var text):
        guard let count = Int32(exactly: text.utf8.count) else {
          throw DatabaseFailure.textTooLarge
        }
        // SQLite copies the bytes, so the string's own UTF-8 storage needs no C string copy.
        // An empty string may have no storage, and a null pointer would bind NULL instead of empty text.
        status = text.withUTF8 { bytes in
          guard let base = bytes.baseAddress, count > 0 else {
            return sqlite3_bind_text(statement, position, "", 0, gymemo_sqlite_transient())
          }
          return base.withMemoryRebound(to: CChar.self, capacity: bytes.count) {
            sqlite3_bind_text(statement, position, $0, count, gymemo_sqlite_transient())
          }
        }
      case .integer(let number):
        status = sqlite3_bind_int64(statement, position, number)
      case .null:
        status = sqlite3_bind_null(statement, position)
      }
      guard status == SQLITE_OK else { throw failure(status) }
    }
  }
}
