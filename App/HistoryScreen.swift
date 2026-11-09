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
      Image(systemName: "chevron.right")
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

  var body: some View {
    let history = model.log.history
    NavigationStack(path: $path) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if history.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
              Text("記録はまだありません。").accessibilityIdentifier("empty-history")
              Button(action: openLog) {
                Label("今日の記録を始める", systemImage: "square.and.pencil")
              }
              .buttonStyle(MonoButtonStyle(prominent: true))
            }
            .padding(.bottom, 24)
          }
          Button {
            isPickingDay = true
          } label: {
            Label("日付を選んで記録", systemImage: "calendar.badge.plus")
          }
          .buttonStyle(MonoButtonStyle())
          .padding(.bottom, 16)
          ForEach(history) { summary in
            NavigationLink(value: summary.day) {
              LinkRow { DayRow(summary: summary) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("day-\(summary.day.iso)")
          }
        }
        .padding(16)
      }
      .background(.surface)
      .navigationTitle("履歴")
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
      Label(Format.longDay(summary.day), systemImage: "calendar").font(.body.weight(.bold))
      if summary.setCount > 0 {
        Text("\(summary.exerciseNames.map(\.text).joined(separator: "、"))　\(summary.setCount)セット")
          .font(.subheadline)
          .multilineTextAlignment(.leading)
      }
      if let memo = summary.memo {
        Label(memo.text, systemImage: "note.text").font(.subheadline).lineLimit(1)
      }
    }
  }
}

/// Picks any day up to today, so the lifter can log or correct a past day.
private struct DayPicker: View {
  let today: LocalDay
  let open: (LocalDay) -> Void
  @State private var date: Date

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  init(today: LocalDay, open: @escaping (LocalDay) -> Void) {
    self.today = today
    self.open = open
    _date = State(initialValue: today.noonUTC)
  }

  var body: some View {
    SheetFrame(title: "日付を選ぶ", confirmTitle: "開く", confirmIcon: "arrow.right") {
      open(LocalDay.nearest(to: date, in: .gmt))
    } content: {
      DatePicker(
        "記録する日", selection: $date, in: LocalDay.earliest.noonUTC...today.noonUTC,
        displayedComponents: .date
      )
      .datePickerStyle(.graphical)
      .environment(\.timeZone, .gmt)
      .environment(\.calendar, Self.calendar)
      .environment(\.locale, Locale(identifier: "ja_JP"))
      Text("選んだ日の記録を開きます。今日より先の日は選べません。").font(.subheadline)
    }
  }
}
