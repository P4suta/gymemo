import GymemoCopy
import GymemoCore
import GymemoKit
import SwiftUI

/// Every recorded day from newest to oldest, under a header for each month.
struct HistoryScreen: View {
  let openLog: () -> Void
  @State private var selectedDay: LocalDay?
  @State private var compactColumn = NavigationSplitViewColumn.sidebar

  var body: some View {
    NavigationSplitView(preferredCompactColumn: $compactColumn) {
      HistoryList(selectedDay: $selectedDay, openLog: openLog) { day in
        selectedDay = day
        compactColumn = .detail
      }
    } detail: {
      HistoryDetail(day: selectedDay)
    }
    .navigationSplitViewStyle(.balanced)
  }
}

struct HistoryDetail: View {
  let day: LocalDay?

  var body: some View {
    if let day {
      DayScreen(day: day).id(day)
    } else {
      ContentUnavailableView(copy[.chooseDay], systemImage: "calendar")
    }
  }
}

struct HistoryList: View {
  @Binding var selectedDay: LocalDay?
  let openLog: () -> Void
  let openPickedDay: (LocalDay) -> Void
  @Environment(AppModel.self) private var model
  @State private var isPickingDay = false

  var body: some View {
    let months = model.log.historyByMonth
    List(selection: $selectedDay) {
      ForEach(months) { month in
        Section(copy.day(month.start, .month)) {
          ForEach(month.days) { summary in
            NavigationLink(value: summary.day) {
              DayRow(summary: summary, isSelected: selectedDay == summary.day)
            }
            .accessibilityIdentifier("day-\(summary.day.iso)")
          }
        }
      }
    }
    .overlay {
      if months.isEmpty {
        ContentUnavailableView {
          Label(copy[.historyEmpty], systemImage: "clock")
            .accessibilityIdentifier("empty-history")
        } actions: {
          Button(copy[.startToday], action: openLog)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("start-today")
        }
      }
    }
    .navigationTitle(copy[.tabHistory])
    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
    #if os(macOS)
      .listStyle(.inset)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(copy[.logAnotherDay], systemImage: "calendar.badge.plus") { isPickingDay = true }
          .accessibilityIdentifier("log-another-day")
      }
    }
    .sheet(isPresented: $isPickingDay) {
      DayPicker(today: model.today) { day in
        isPickingDay = false
        openPickedDay(day)
      }
    }
  }
}

private struct DayRow: View {
  let summary: DaySummary
  let isSelected: Bool

  var body: some View {
    StackedRow(
      title: copy.day(summary.day, .long),
      subtitle: summary.setCount > 0
        ? copy.historyRow(exercises: summary.exerciseNames.map(\.text), setCount: summary.setCount)
        : nil,
      caption: summary.memo?.preview(limit: 60), isEmphasized: true, isSelected: isSelected)
  }
}

/// Picks any day up to today, so the lifter can log or correct a past day.
private struct DayPicker: View {
  let today: LocalDay
  let open: (LocalDay) -> Void
  @State private var date: Date

  init(today: LocalDay, open: @escaping (LocalDay) -> Void) {
    self.today = today
    self.open = open
    _date = State(initialValue: today.noonUTC)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          DatePicker(
            copy[.dayToLog], selection: $date, in: LocalDay.earliest.noonUTC...today.noonUTC,
            displayedComponents: .date
          )
          .datePickerStyle(.graphical)
          .environment(\.timeZone, .gmt)
          .environment(\.calendar, copy.calendar)
          .environment(\.locale, copy.locale)
          .accessibilityIdentifier("day-picker")
        } footer: {
          Text(copy[.chooseDayHint])
        }
      }
      .sheetToolbar(title: copy[.chooseDay], confirmTitle: copy[.open], isDirty: false) {
        open(LocalDay.nearest(to: date, in: .gmt))
      }
    }
  }
}
