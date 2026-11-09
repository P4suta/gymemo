import CSQLite
import Foundation

enum SQLValue: Equatable {
  case text(String)
  case integer(Int64)
  case null
}

/// One row that a statement currently points at, valid only inside the closure that receives it.
struct SQLiteRow {
  fileprivate let statement: OpaquePointer

  func text(_ column: Int32, maximumBytes: Int = 1_048_576) throws(StoreFailure) -> String {
    let count = Int(sqlite3_column_bytes(statement, column))
    guard count <= maximumBytes else { throw .textTooLarge }
    guard let pointer = sqlite3_column_text(statement, column),
      let value = String(bytes: UnsafeBufferPointer(start: pointer, count: count), encoding: .utf8)
    else { throw .invalidText }
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

  init(url: URL) throws(StoreFailure) {
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
    let status = sqlite3_open_v2(url.path, &handle, flags, nil)
    // A failed open usually still returns a connection, and that connection holds the message.
    // Swift runs `deinit` when an initializer throws after every stored property has a value, so `deinit` closes it.
    guard status == SQLITE_OK else { throw failure(status) }
    sqlite3_busy_timeout(handle, 5_000)
    // SQLite leaves foreign key enforcement off for each new connection.
    // See https://www.sqlite.org/pragma.html#pragma_foreign_keys.
    try execute("PRAGMA foreign_keys = ON")
  }

  deinit { sqlite3_close_v2(handle) }

  func close() throws(StoreFailure) {
    guard handle != nil else { return }
    let status = sqlite3_close(handle)
    guard status == SQLITE_OK else { throw failure(status) }
    handle = nil
  }

  func query<Value>(
    _ sql: String, _ values: [SQLValue] = [], row: (SQLiteRow) throws(StoreFailure) -> Value
  ) throws(StoreFailure) -> [Value] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(values, to: statement)
    var rows: [Value] = []
    try run(statement) { current throws(StoreFailure) in rows.append(try row(current)) }
    return rows
  }

  func execute(_ sql: String, _ values: [SQLValue] = []) throws(StoreFailure) {
    _ = try query(sql, values) { _ in () }
  }

  /// Runs one statement for each row of values, preparing it only once.
  func batch(_ sql: String, _ rows: [[SQLValue]]) throws(StoreFailure) {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    for values in rows {
      sqlite3_reset(statement)
      try bind(values, to: statement)
      try run(statement) { _ in }
    }
  }

  /// Runs `body` so that the database stores all its changes or none.
  /// A failed rollback never hides the error that caused it.
  func transaction<Value>(
    _ body: () throws(StoreFailure) -> Value
  ) throws(StoreFailure) -> Value {
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

  private func failure(_ code: Int32) -> StoreFailure {
    .sqlite(code: code, message: String(cString: sqlite3_errmsg(handle)))
  }

  private func prepare(_ sql: String) throws(StoreFailure) -> OpaquePointer {
    var prepared: OpaquePointer?
    let status = sqlite3_prepare_v2(handle, sql, -1, &prepared, nil)
    // SQLite leaves no statement behind when it reports an error, so this failure has none to release.
    guard status == SQLITE_OK, let statement = prepared else { throw failure(status) }
    return statement
  }

  /// Steps `statement` to its end and gives each of its rows to `row`.
  private func run(
    _ statement: OpaquePointer, row: (SQLiteRow) throws(StoreFailure) -> Void
  ) throws(StoreFailure) {
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW: try row(SQLiteRow(statement: statement))
      case SQLITE_DONE: return
      case let code: throw failure(code)
      }
    }
  }

  /// Once this returns, every parameter of `statement` holds its value from `values`, so a statement that runs again keeps none of its earlier values.
  private func bind(_ values: [SQLValue], to statement: OpaquePointer) throws(StoreFailure) {
    guard sqlite3_bind_parameter_count(statement) == values.count else {
      throw .parameterCount
    }
    for (index, value) in values.enumerated() {
      let position = Int32(index + 1)
      let status: Int32
      switch value {
      case .text(var text):
        guard let count = Int32(exactly: text.utf8.count) else { throw .textTooLarge }
        // SQLite copies the bytes, so the string's own UTF-8 storage needs no C string copy.
        // An empty string may have no storage, and a null pointer would bind NULL instead of empty text.
        status = text.withUTF8 { bytes in
          guard let base = bytes.baseAddress else {
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
