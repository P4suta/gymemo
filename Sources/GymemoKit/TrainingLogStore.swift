import CryptoKit
import Foundation
import GymemoCore

/// The one SQLite file that holds the training log.
/// A single owner uses a store from one thread at a time.
/// `docs/adr/store-the-training-log-in-one-sqlite-file.md` records the design.
public final class TrainingLogStore {
  /// The number in `PRAGMA user_version` of a file that this code reads and writes.
  public static let schemaVersion = 2

  private static let receiptSchema = """
    CREATE TABLE companion_receipt (
      id TEXT PRIMARY KEY NOT NULL CHECK (typeof(id) = 'text'),
      fingerprint TEXT NOT NULL CHECK (typeof(fingerprint) = 'text')
    )
    """

  private static let schema = [
    """
    CREATE TABLE exercise (
      id TEXT PRIMARY KEY NOT NULL CHECK (typeof(id) = 'text'),
      position INTEGER NOT NULL UNIQUE CHECK (typeof(position) = 'integer'),
      name TEXT NOT NULL UNIQUE CHECK (typeof(name) = 'text'),
      body_part TEXT NOT NULL CHECK (typeof(body_part) = 'text'),
      archived INTEGER NOT NULL CHECK (archived IN (0, 1))
    )
    """,
    """
    CREATE TABLE logged_set (
      id TEXT PRIMARY KEY NOT NULL CHECK (typeof(id) = 'text'),
      position INTEGER NOT NULL UNIQUE CHECK (typeof(position) = 'integer'),
      exercise_id TEXT NOT NULL REFERENCES exercise (id),
      day TEXT NOT NULL CHECK (typeof(day) = 'text'),
      weight_hundredths INTEGER NOT NULL
        CHECK (typeof(weight_hundredths) = 'integer' AND weight_hundredths BETWEEN 0 AND 99999),
      reps INTEGER NOT NULL CHECK (typeof(reps) = 'integer' AND reps BETWEEN 1 AND 999)
    )
    """,
    "CREATE INDEX logged_set_exercise ON logged_set (exercise_id)",
    """
    CREATE TABLE day_memo (
      day TEXT PRIMARY KEY NOT NULL CHECK (typeof(day) = 'text'),
      text TEXT NOT NULL CHECK (typeof(text) = 'text')
    )
    """,
  ]

  private let database: SQLiteDatabase

  /// Opens the file at `url`, and creates it with `starter` when it doesn't exist yet.
  public init(url: URL, starter: TrainingLog) throws(StoreFailure) {
    do {
      database = try SQLiteDatabase(url: url)
      // The pragma reference advises EXTRA where a commit must survive a power loss in rollback mode.
      // See https://www.sqlite.org/pragma.html#pragma_synchronous.
      try database.execute("PRAGMA synchronous = EXTRA")
      try Self.prepare(database, starter: starter)
    } catch {
      StoreTrace.failed(.open, error)
      throw error
    }
  }

  public func load() throws(StoreFailure) -> TrainingLog {
    do {
      return try read()
    } catch {
      StoreTrace.failed(.load, error)
      throw error
    }
  }

  /// Stores every change or none of them.
  public func apply(_ changes: [Change]) throws(StoreFailure) {
    guard !changes.isEmpty else { return }
    do {
      try database.transaction { () throws(StoreFailure) in
        for change in changes {
          try write(change)
        }
      }
    } catch {
      StoreTrace.failed(.apply, error)
      throw error
    }
  }

  public func receive(_ set: LoggedSet) throws(StoreFailure) -> (
    log: TrainingLog, receipt: CompanionReceipt
  ) {
    do {
      return try database.transaction { () throws(StoreFailure) in
        let log = try read()
        guard let data = try? CompanionCodec.encode(.entry(set)) else {
          throw .corruptRow(table: "companion_receipt")
        }
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let stored = try database.query(
          "SELECT fingerprint FROM companion_receipt WHERE id = ?", [.text(set.id.uuid.uuidString)]
        ) { row throws(StoreFailure) in try row.text(0) }
        if let previous = stored.first {
          let outcome: CompanionOutcome = previous == fingerprint ? .saved : .identifierConflict
          return (log, CompanionReceipt(set: set, outcome: outcome))
        }
        if let existing = log.set(set.id), existing != set {
          return (log, CompanionReceipt(set: set, outcome: .identifierConflict))
        }
        var committed = log
        if log.set(set.id) == nil {
          switch log.apply(
            .logSet(
              id: set.id, exerciseID: set.exerciseID, day: set.day, weight: set.weight,
              reps: set.reps)
          ) {
          case .success(let transition):
            for change in transition.changes { try write(change) }
            committed = transition.log
          case .failure(let refusal):
            let outcome: CompanionOutcome = refusal == .unknownExercise ? .unknownExercise : .full
            return (log, CompanionReceipt(set: set, outcome: outcome))
          }
        }
        try database.execute(
          "INSERT INTO companion_receipt (id, fingerprint) VALUES (?, ?)",
          [.text(set.id.uuid.uuidString), .text(fingerprint)])
        return (committed, CompanionReceipt(set: set, outcome: .saved))
      }
    } catch {
      StoreTrace.failed(.apply, error)
      throw error
    }
  }

  private static func prepare(
    _ database: SQLiteDatabase, starter: TrainingLog
  ) throws(StoreFailure) {
    let version = try database.query("PRAGMA user_version") { row in Int(row.integer(0)) }
    switch version.first ?? 0 {
    case schemaVersion:
      return
    case 1:
      try database.transaction { () throws(StoreFailure) in
        try database.execute(receiptSchema)
        try database.execute("PRAGMA user_version = \(schemaVersion)")
      }
    case 0:
      let objects = try database.query("SELECT count(*) FROM sqlite_master") { row in
        row.integer(0)
      }
      guard objects == [0] else { throw .unsupportedSchema(version: 0) }
      try database.transaction { () throws(StoreFailure) in
        for statement in schema {
          try database.execute(statement)
        }
        try database.execute(receiptSchema)
        try insert(starter, into: database)
        try database.execute("PRAGMA user_version = \(schemaVersion)")
      }
    case let other:
      throw .unsupportedSchema(version: other)
    }
  }

  private static func insert(
    _ log: TrainingLog, into database: SQLiteDatabase
  ) throws(StoreFailure) {
    try database.batch(
      "INSERT INTO exercise (id, position, name, body_part, archived) VALUES (?, ?, ?, ?, ?)",
      log.exercises.enumerated().map { position, exercise in
        [.text(exercise.id.uuid.uuidString), .integer(Int64(position))] + values(of: exercise)
      })
    try database.batch(
      """
      INSERT INTO logged_set (id, position, exercise_id, day, weight_hundredths, reps)
      VALUES (?, ?, ?, ?, ?, ?)
      """,
      log.sets.enumerated().map { position, set in
        [.text(set.id.uuid.uuidString), .integer(Int64(position))] + values(of: set)
      })
    try database.batch(
      "INSERT INTO day_memo (day, text) VALUES (?, ?)",
      log.memos.map { day, memo in [.text(day.iso), .text(memo.text)] })
  }

  private static func values(of exercise: Exercise) -> [SQLValue] {
    [
      .text(exercise.name.text), .text(exercise.bodyPart.rawValue),
      .integer(exercise.isArchived ? 1 : 0),
    ]
  }

  private static func values(of set: LoggedSet) -> [SQLValue] {
    [
      .text(set.exerciseID.uuid.uuidString), .text(set.day.iso),
      .integer(Int64(set.weight.hundredths)), .integer(Int64(set.reps.count)),
    ]
  }

  private func read() throws(StoreFailure) -> TrainingLog {
    let exercises = try database.query(
      "SELECT id, name, body_part, archived FROM exercise ORDER BY position"
    ) { row throws(StoreFailure) -> Exercise in
      guard let uuid = UUID(uuidString: try row.text(0)),
        case .success(let name) = ExerciseName.parse(try row.text(1)),
        let bodyPart = BodyPart(rawValue: try row.text(2))
      else { throw .corruptRow(table: "exercise") }
      return Exercise(
        id: ExerciseID(uuid), name: name, bodyPart: bodyPart, isArchived: row.integer(3) != 0)
    }
    let sets = try database.query(
      "SELECT id, exercise_id, day, weight_hundredths, reps FROM logged_set ORDER BY position"
    ) { row throws(StoreFailure) -> LoggedSet in
      guard let uuid = UUID(uuidString: try row.text(0)),
        let exercise = UUID(uuidString: try row.text(1)), let day = LocalDay(iso: try row.text(2)),
        let hundredths = Int(exactly: row.integer(3)), let weight = Weight(hundredths: hundredths),
        let count = Int(exactly: row.integer(4)), let reps = Reps(count)
      else { throw .corruptRow(table: "logged_set") }
      return LoggedSet(
        id: SetID(uuid), exerciseID: ExerciseID(exercise), day: day, weight: weight, reps: reps)
    }
    let memoRows = try database.query("SELECT day, text FROM day_memo") {
      row throws(StoreFailure) -> (LocalDay, Memo) in
      guard let day = LocalDay(iso: try row.text(0)),
        case .success(let memo?) = Memo.parse(try row.text(1))
      else { throw .corruptRow(table: "day_memo") }
      return (day, memo)
    }
    let memos = Dictionary(memoRows, uniquingKeysWith: { first, _ in first })
    switch TrainingLog.make(exercises: exercises, sets: sets, memos: memos) {
    case .success(let log): return log
    case .failure(let refusal): throw .integrity(refusal)
    }
  }

  private func write(_ change: Change) throws(StoreFailure) {
    switch change {
    case .putExercise(let exercise):
      try database.execute(
        """
        INSERT INTO exercise (id, position, name, body_part, archived)
        VALUES (?, (SELECT COALESCE(MAX(position), -1) + 1 FROM exercise), ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET
          name = excluded.name, body_part = excluded.body_part, archived = excluded.archived
        """,
        [.text(exercise.id.uuid.uuidString)] + Self.values(of: exercise))
    case .removeExercise(let id):
      try database.execute("DELETE FROM exercise WHERE id = ?", [.text(id.uuid.uuidString)])
    case .putSet(let set):
      try database.execute(
        """
        INSERT INTO logged_set (id, position, exercise_id, day, weight_hundredths, reps)
        VALUES (?, (SELECT COALESCE(MAX(position), -1) + 1 FROM logged_set), ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET
          exercise_id = excluded.exercise_id, day = excluded.day,
          weight_hundredths = excluded.weight_hundredths, reps = excluded.reps
        """,
        [.text(set.id.uuid.uuidString)] + Self.values(of: set))
    case .removeSet(let id):
      try database.execute("DELETE FROM logged_set WHERE id = ?", [.text(id.uuid.uuidString)])
    case .putMemo(let day, let memo):
      try database.execute(
        """
        INSERT INTO day_memo (day, text) VALUES (?, ?)
        ON CONFLICT (day) DO UPDATE SET text = excluded.text
        """,
        [.text(day.iso), .text(memo.text)])
    case .removeMemo(let day):
      try database.execute("DELETE FROM day_memo WHERE day = ?", [.text(day.iso)])
    case .replaceAll(let log):
      for table in ["logged_set", "exercise", "day_memo"] {
        try database.execute("DELETE FROM \(table)")
      }
      try Self.insert(log, into: database)
    }
  }
}
