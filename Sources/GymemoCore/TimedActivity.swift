import Foundation

public struct TimedActivityID: Hashable, Sendable {
  public static let walking = Self(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)))
  public let uuid: UUID

  public init(_ uuid: UUID) {
    self.uuid = uuid
  }
}

public struct TimedActivity: Hashable, Identifiable, Sendable {
  public static let walking = Self()

  public let id: TimedActivityID
  public let name: ExerciseName?
  public let tracksDistance: Bool

  public init?(id: TimedActivityID, name: ExerciseName, tracksDistance: Bool) {
    guard id != .walking else { return nil }
    self.id = id
    self.name = name
    self.tracksDistance = tracksDistance
  }

  private init() {
    id = .walking
    name = nil
    tracksDistance = true
  }
}

public struct ActivityDuration: Hashable, Sendable {
  public static let maximumMinutes = 1_440
  public let minutes: Int

  public init?(minutes: Int) {
    guard (1...Self.maximumMinutes).contains(minutes) else { return nil }
    self.minutes = minutes
  }

  public static func parse(_ text: String) -> Self? {
    guard let minutes = text.trimmedWhitespace.asciiNumber(limit: maximumMinutes) else {
      return nil
    }
    return Self(minutes: minutes)
  }
}

public struct ActivityDistance: Hashable, Sendable {
  public static let maximumMeters = 1_000_000
  public let meters: Int

  public init?(meters: Int) {
    guard (1...Self.maximumMeters).contains(meters) else { return nil }
    self.meters = meters
  }
}

public struct LoggedActivityID: Hashable, Sendable {
  public let uuid: UUID

  public init(_ uuid: UUID) {
    self.uuid = uuid
  }
}

public struct LoggedActivity: Hashable, Identifiable, Sendable {
  public let id: LoggedActivityID
  public let activityID: TimedActivityID
  public let day: LocalDay
  public var duration: ActivityDuration
  public var distance: ActivityDistance?

  public init(
    id: LoggedActivityID, activityID: TimedActivityID, day: LocalDay,
    duration: ActivityDuration, distance: ActivityDistance?
  ) {
    self.id = id
    self.activityID = activityID
    self.day = day
    self.duration = duration
    self.distance = distance
  }
}
