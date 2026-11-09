import Foundation
import GymemoCore
import Testing

@Suite struct LocalDayTests {
  @Test(arguments: [
    (2026, 2, 29), (2026, 13, 1), (2026, 0, 1), (2026, 11, 0), (2026, 11, 31), (1899, 12, 31),
    (2201, 1, 1), (2100, 2, 29),
  ])
  func refusesDaysOutsideTheCalendarOrTheSupportedYears(year: Int, month: Int, day: Int) {
    #expect(LocalDay(year: year, month: month, day: day) == nil)
  }

  @Test(arguments: [(2024, 2, 29), (2000, 2, 29), (1900, 1, 1), (2200, 12, 31), (2026, 11, 9)])
  func keepsTheYearMonthAndDay(year: Int, month: Int, day: Int) throws {
    let value = try #require(LocalDay(year: year, month: month, day: day))
    #expect(value.year == year)
    #expect(value.month == month)
    #expect(value.day == day)
  }

  @Test func agreesWithTheGregorianCalendarOnEverySupportedDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let weekdays: [Weekday] = [
      .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
    ]
    var previous: LocalDay?
    for number in LocalDay.earliest.dayNumber...LocalDay.latest.dayNumber {
      let day = try #require(LocalDay(dayNumber: number))
      let date = Date(timeIntervalSince1970: TimeInterval(number) * 86_400)
      let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
      let matches =
        day.year == parts.year && day.month == parts.month && day.day == parts.day
        && parts.weekday.map { weekdays[$0 - 1] } == day.weekday
        && LocalDay(year: day.year, month: day.month, day: day.day) == day
      if !matches {
        Issue.record("Day number \(number) became \(day.iso)")
        return
      }
      if let previous { #expect(previous < day) }
      previous = day
    }
    #expect(LocalDay.earliest.iso == "1900-01-01")
    #expect(LocalDay.latest.iso == "2200-12-31")
    #expect(LocalDay(dayNumber: LocalDay.earliest.dayNumber - 1) == nil)
    #expect(LocalDay(dayNumber: LocalDay.latest.dayNumber + 1) == nil)
  }

  @Test func weeksStartOnMonday() throws {
    let monday = try #require(LocalDay(year: 2026, month: 11, day: 9))
    let sunday = try #require(LocalDay(year: 2026, month: 11, day: 15))
    let nextMonday = try #require(LocalDay(year: 2026, month: 11, day: 16))
    #expect(monday.weekday == .monday)
    #expect(sunday.weekday == .sunday)
    #expect(monday.weekStart == monday)
    #expect(sunday.weekStart == monday)
    #expect(nextMonday.weekStart == nextMonday)
    #expect(LocalDay.earliest.weekStart == LocalDay.earliest)
  }

  @Test func addsDaysWithinTheSupportedYears() throws {
    let day = try #require(LocalDay(year: 2026, month: 12, day: 31))
    #expect(day.adding(days: 1)?.iso == "2027-01-01")
    #expect(day.adding(days: -365)?.iso == "2025-12-31")
    #expect(LocalDay.latest.adding(days: 1) == nil)
    #expect(LocalDay.earliest.adding(days: -1) == nil)
    #expect(day.adding(days: .max) == nil)
    #expect(day.adding(days: .min) == nil)
  }

  @Test(arguments: ["2026-11-09", "1900-01-01", "2200-12-31", "2024-02-29"])
  func readsItsOwnText(text: String) {
    #expect(LocalDay(iso: text)?.iso == text)
  }

  @Test(arguments: [
    "", "2026-11-9", "2026/11/09", "2026-11-09 ", "2026-02-30", "20261109", "2026-11-09T00:00",
    "２０２６-11-09", "+026-11-09", "2026-1a-09",
  ])
  func refusesOtherText(text: String) {
    #expect(LocalDay(iso: text) == nil)
  }
}
