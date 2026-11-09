import GymemoCopy
import GymemoCore
import GymemoKit
import SwiftUI

/// The label of a row that opens another screen.
struct LinkRow<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(spacing: 12) {
      content()
      Spacer(minLength: 8)
      Image(systemName: "chevron.right").accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .overlay(alignment: .bottom) { Rule() }
  }
}

/// Every recorded day from newest to oldest.
struct HistoryScreen: View {
  let openLog: () -> Void
  @Environment(AppModel.self) private var model
  @State private var path: [LocalDay] = []
  @State private var isPickingDay = false
  @State private var shownDays = pageSize

  private static let pageSize = 20

  var body: some View {
    let history = model.log.history
    NavigationStack(path: $path) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if history.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
              Text(copy[.historyEmpty]).accessibilityIdentifier("empty-history")
              Button(action: openLog) {
                Label(copy[.startToday], systemImage: "square.and.pencil")
              }
              .buttonStyle(MonoButtonStyle(prominent: true))
              .accessibilityIdentifier("start-today")
            }
            .padding(.bottom, 24)
          }
          Button {
            isPickingDay = true
          } label: {
            Label(copy[.logAnotherDay], systemImage: "calendar.badge.plus")
          }
          .buttonStyle(MonoButtonStyle())
          .padding(.bottom, 16)
          .accessibilityIdentifier("log-another-day")
          // The list draws every shown row at once, so each row keeps its size at every text size.
          // It shows the newest days first and adds older ones on request, which bounds that work.
          ForEach(history.prefix(shownDays)) { summary in
            NavigationLink(value: summary.day) {
              LinkRow { DayRow(summary: summary) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("day-\(summary.day.iso)")
          }
          if history.count > shownDays {
            Button {
              shownDays += Self.pageSize
            } label: {
              Label(copy[.showOlderDays], systemImage: "chevron.down")
            }
            .buttonStyle(MonoButtonStyle())
            .padding(.top, 16)
            .accessibilityIdentifier("show-older-days")
          }
        }
        .padding(16)
      }
      .screenSurface()
      .navigationTitle(copy[.tabHistory])
      .navigationDestination(for: LocalDay.self) { day in
        DayScreen(day: day)
      }
      .sheet(isPresented: $isPickingDay) {
        DayPicker(today: model.today) { day in
          isPickingDay = false
          path = [day]
        }
      }
    }
  }
}

private struct DayRow: View {
  let summary: DaySummary

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(copy.day(summary.day, .long), systemImage: "calendar").font(.body.weight(.bold))
      if summary.setCount > 0 {
        Text(
          copy.historyRow(
            exercises: summary.exerciseNames.map(\.text), setCount: summary.setCount)
        )
        .font(.subheadline)
        .multilineTextAlignment(.leading)
      }
      if let note = summary.memo {
        Label(note.preview(limit: 60), systemImage: "note.text")
          .font(.subheadline)
          .multilineTextAlignment(.leading)
      }
    }
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
    SheetFrame(title: copy[.chooseDay], confirmTitle: copy[.open], confirmIcon: "arrow.right") {
      open(LocalDay.nearest(to: date, in: .gmt))
    } content: {
      DatePicker(
        copy[.dayToLog], selection: $date, in: LocalDay.earliest.noonUTC...today.noonUTC,
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .environment(\.timeZone, .gmt)
      .environment(\.calendar, copy.calendar)
      .environment(\.locale, copy.locale)
      .accessibilityIdentifier("day-picker")
      Text(copy[.chooseDayHint]).font(.subheadline)
    }
  }
}
