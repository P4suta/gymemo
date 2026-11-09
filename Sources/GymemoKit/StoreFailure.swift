import GymemoCore
import os

public enum StoreFailure: Error, Equatable, Sendable {
  case sqlite(code: Int32, message: String)
  case parameterCount
  case textTooLarge
  case invalidText
  case unsupportedSchema(version: Int)
  case corruptRow(table: String)
  case integrity(IntegrityRefusal)

  /// A number that names the failure in a log line without any stored text.
  /// SQLite's result codes are positive, and the store's own failures are negative.
  public var code: Int32 {
    switch self {
    case .sqlite(let code, _): code
    case .parameterCount: -1
    case .textTooLarge: -2
    case .invalidText: -3
    case .unsupportedSchema: -4
    case .corruptRow: -5
    case .integrity: -6
    }
  }
}

enum StoreOperation: String {
  case open
  case load
  case apply
}

enum StoreTrace {
  private static let logger = Logger(subsystem: "com.p4suta.gymemo", category: "store")

  static func failed(_ operation: StoreOperation, _ failure: StoreFailure) {
    let code = failure.code
    logger.error(
      "store.\(operation.rawValue, privacy: .public) failed code=\(code, privacy: .public)")
  }
}
