public enum ActivityCommand: Equatable, Sendable {
  case add(id: TimedActivityID, name: String, tracksDistance: Bool)
  case record(LoggedActivity)
  case edit(LoggedActivityID, duration: ActivityDuration, distance: ActivityDistance?)
  case delete(LoggedActivityID)
}

public enum ActivityChange: Equatable, Sendable {
  case putActivity(TimedActivity)
  case putRecord(LoggedActivity)
  case removeRecord(LoggedActivityID)
}

public enum ActivityRefusal: Error, Equatable, Sendable {
  case name(ExerciseNameRefusal)
  case duplicateName
  case duplicateIdentifier
  case unknownActivity
  case unknownRecord
  case unexpectedDistance
  case full
}

public struct ActivityTransition: Equatable, Sendable {
  public let log: TrainingLog
  public let changes: [ActivityChange]
}

public struct ActivityLog: Equatable, Sendable {
  public static let empty = ActivityLog(customActivities: [], records: [])
  public let customActivities: [TimedActivity]
  public let records: [LoggedActivity]

  private let definitionsByID: [TimedActivityID: TimedActivity]
  private let recordPositions: [LoggedActivityID: Int]
  private let recordsByDay: [LocalDay: [LoggedActivity]]

  public var choices: [TimedActivity] { [.walking] + customActivities }
  public var days: Set<LocalDay> { Set(recordsByDay.keys) }

  fileprivate init(customActivities: [TimedActivity], records: [LoggedActivity]) {
    self.customActivities = customActivities
    self.records = records
    definitionsByID = Dictionary(uniqueKeysWithValues: customActivities.map { ($0.id, $0) })
    recordPositions = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($1.id, $0) })
    recordsByDay = Dictionary(grouping: records, by: \.day)
  }

  public static func make(
    customActivities: [TimedActivity], records: [LoggedActivity]
  ) -> Result<ActivityLog, ActivityRefusal> {
    guard customActivities.count <= TrainingLog.maximumExercises,
      records.count <= TrainingLog.maximumSets
    else { return .failure(.full) }
    let names = Set(customActivities.compactMap(\.name))
    guard !customActivities.contains(.walking),
      Set(customActivities.map(\.id)).count == customActivities.count,
      Set(records.map(\.id)).count == records.count
    else { return .failure(.duplicateIdentifier) }
    guard names.count == customActivities.count else { return .failure(.duplicateName) }
    let log = ActivityLog(customActivities: customActivities, records: records)
    for record in records {
      if let refusal = log.measurementRefusal(for: record) { return .failure(refusal) }
    }
    return .success(log)
  }

  public func activity(_ id: TimedActivityID) -> TimedActivity? {
    id == .walking ? .walking : definitionsByID[id]
  }

  public func records(on day: LocalDay) -> [LoggedActivity] { recordsByDay[day] ?? [] }

  fileprivate func position(of id: LoggedActivityID) -> Int? { recordPositions[id] }

  fileprivate func measurementRefusal(for record: LoggedActivity) -> ActivityRefusal? {
    guard let activity = activity(record.activityID) else { return .unknownActivity }
    return record.distance != nil && !activity.tracksDistance ? .unexpectedDistance : nil
  }
}

extension TrainingLog {
  public func apply(_ command: ActivityCommand) -> Result<ActivityTransition, ActivityRefusal> {
    switch command {
    case .add(let id, let name, let tracksDistance):
      return addActivity(id: id, name: name, tracksDistance: tracksDistance)
    case .record(let record):
      if let refusal = activities.measurementRefusal(for: record) { return .failure(refusal) }
      guard activities.position(of: record.id) == nil else { return .failure(.duplicateIdentifier) }
      guard activities.records.count < Self.maximumSets else { return .failure(.full) }
      return .success(withActivities(records: activities.records + [record], .putRecord(record)))
    case .edit(let id, let duration, let distance):
      guard let position = activities.position(of: id) else { return .failure(.unknownRecord) }
      var revised = activities.records
      let original = revised[position]
      revised[position].duration = duration
      revised[position].distance = distance
      let edited = revised[position]
      if let refusal = activities.measurementRefusal(for: edited) { return .failure(refusal) }
      guard edited != original else { return .success(ActivityTransition(log: self, changes: [])) }
      return .success(withActivities(records: revised, .putRecord(edited)))
    case .delete(let id):
      guard let position = activities.position(of: id) else { return .failure(.unknownRecord) }
      var remaining = activities.records
      remaining.remove(at: position)
      return .success(withActivities(records: remaining, .removeRecord(id)))
    }
  }

  private func addActivity(
    id: TimedActivityID, name: String, tracksDistance: Bool
  ) -> Result<ActivityTransition, ActivityRefusal> {
    ExerciseName.parse(name).mapError(ActivityRefusal.name).flatMap { name in
      guard activities.activity(id) == nil,
        let added = TimedActivity(id: id, name: name, tracksDistance: tracksDistance)
      else { return .failure(.duplicateIdentifier) }
      guard !activities.customActivities.contains(where: { $0.name == name }) else {
        return .failure(.duplicateName)
      }
      guard activities.customActivities.count < Self.maximumExercises else {
        return .failure(.full)
      }
      return .success(
        withActivities(customActivities: activities.customActivities + [added], .putActivity(added))
      )
    }
  }

  private func withActivities(
    customActivities: [TimedActivity]? = nil, records: [LoggedActivity]? = nil,
    _ change: ActivityChange
  ) -> ActivityTransition {
    let activityLog = ActivityLog(
      customActivities: customActivities ?? activities.customActivities,
      records: records ?? activities.records)
    let log = TrainingLog(
      unchecked: exercises, sets: sets, memos: memos, activities: activityLog)
    return ActivityTransition(log: log, changes: [change])
  }
}
