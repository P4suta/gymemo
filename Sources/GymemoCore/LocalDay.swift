public enum Weekday: Int, CaseIterable, Sendable {
  case monday, tuesday, wednesday, thursday, friday, saturday, sunday
}

/// One day of the Gregorian calendar from 1900-01-01 to 2200-12-31, with no time and no time zone.
public struct LocalDay: Hashable, Comparable, Sendable {
  public static let earliest = LocalDay(unchecked: dayNumber(year: 1900, month: 1, day: 1))
  public static let latest = LocalDay(unchecked: dayNumber(year: 2200, month: 12, day: 31))

  /// The number of days since 1970-01-01.
  public let dayNumber: Int

  public init?(dayNumber: Int) {
    guard (Self.earliest.dayNumber...Self.latest.dayNumber).contains(dayNumber) else {
      return nil
    }
    self.dayNumber = dayNumber
  }

  public init?(year: Int, month: Int, day: Int) {
    guard (1900...2200).contains(year), (1...12).contains(month),
      (1...Self.length(ofMonth: month, year: year)).contains(day)
    else { return nil }
    dayNumber = Self.dayNumber(year: year, month: month, day: day)
  }

  /// Reads the `YYYY-MM-DD` text that `iso` writes.
  public init?(iso: String) {
    let bytes = Array(iso.utf8)
    guard bytes.count == 10, bytes[4] == 0x2D, bytes[7] == 0x2D,
      let year = iso.prefix(4).asciiNumber(limit: 9999),
      let month = iso.dropFirst(5).prefix(2).asciiNumber(limit: 99),
      let day = iso.dropFirst(8).asciiNumber(limit: 99)
    else { return nil }
    self.init(year: year, month: month, day: day)
  }

  private init(unchecked dayNumber: Int) {
    self.dayNumber = dayNumber
  }

  public var year: Int { civil.year }
  public var month: Int { civil.month }
  public var day: Int { civil.day }

  public var weekday: Weekday {
    // 1970-01-01 was a Thursday, the fourth day of a week that starts on Monday.
    Weekday.allCases[((dayNumber % 7) + 10) % 7]
  }

  /// The Monday that starts this day's week.
  /// The earliest supported day is a Monday, so the result stays in range.
  public var weekStart: LocalDay {
    LocalDay(unchecked: dayNumber - weekday.rawValue)
  }

  public var iso: String {
    let parts = civil
    return "\(parts.year)-\(Self.twoDigits(parts.month))-\(Self.twoDigits(parts.day))"
  }

  public func adding(days: Int) -> LocalDay? {
    let (sum, overflow) = dayNumber.addingReportingOverflow(days)
    return overflow ? nil : LocalDay(dayNumber: sum)
  }

  public static func < (left: LocalDay, right: LocalDay) -> Bool {
    left.dayNumber < right.dayNumber
  }

  private static func twoDigits(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
  }

  private static func length(ofMonth month: Int, year: Int) -> Int {
    switch month {
    case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
  }

  // Both conversions count from 0000-03-01, so a leap day ends its year.
  // Every supported year is positive, so integer division needs no floor correction.
  private static func dayNumber(year: Int, month: Int, day: Int) -> Int {
    let shiftedYear = month <= 2 ? year - 1 : year
    let era = shiftedYear / 400
    let yearOfEra = shiftedYear - era * 400
    let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  private var civil: (year: Int, month: Int, day: Int) {
    let shifted = dayNumber + 719_468
    let era = shifted / 146_097
    let dayOfEra = shifted - era * 146_097
    let yearOfEra =
      (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let shiftedMonth = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
    let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return (year, month, day)
  }
}
