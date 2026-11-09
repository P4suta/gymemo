import Foundation
import GymemoCore

extension LocalDay {
  /// The day on which `date` falls in `timeZone`.
  /// The Gregorian calendar applies whatever calendar the device shows.
  public init?(date: Date, timeZone: TimeZone) {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
    // The calendar numbers the years before the common era upward from 1, in an era of their own.
    guard parts.era == 1, let year = parts.year, let month = parts.month, let day = parts.day
    else { return nil }
    self.init(year: year, month: month, day: day)
  }

  /// The day of `date` in `timeZone`, or the supported day nearest to it.
  public static func nearest(to date: Date, in timeZone: TimeZone) -> LocalDay {
    // A time zone differs from UTC by at most 18 hours.
    // A date with no supported day then lies before 1900-01-01T18:00Z or at or after 2200-12-31T06:00Z.
    // The side of 1970 on which it lies names the nearer end of the supported days.
    LocalDay(date: date, timeZone: timeZone)
      ?? (date.timeIntervalSince1970.sign == .minus ? earliest : latest)
  }

  /// Noon of this day in UTC, for a date formatter or a date picker that also works in UTC.
  /// A local time zone can skip a whole day, and UTC never does.
  public var noonUTC: Date {
    Date(timeIntervalSince1970: TimeInterval(dayNumber) * 86_400 + 43_200)
  }
}
