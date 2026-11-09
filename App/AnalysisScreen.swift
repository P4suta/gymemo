import Charts
import GymemoCore
import GymemoKit
import SwiftUI

/// The training days of recent weeks, and each exercise's best score.
struct AnalysisScreen: View {
  let openLog: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let summaries = model.log.exerciseSummaries
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          WeeklyBlock(weeks: model.log.weeklyTrainingDays(through: model.today, weeks: 12))
            .padding(.bottom, 24)
          Rule()
          GroupHeading(text: "種目ごとの推移", icon: "chart.xyaxis.line")
            .padding(.top, 24)
            .padding(.bottom, 8)
          if summaries.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
              Text("セットを記録すると、種目ごとの推移を表示します。")
                .accessibilityIdentifier("empty-analysis")
              Button(action: openLog) {
                Label("今日の記録を始める", systemImage: "square.and.pencil")
              }
              .buttonStyle(MonoButtonStyle(prominent: true))
            }
          }
          ForEach(summaries) { summary in
            NavigationLink(value: summary.exercise.id) {
              LinkRow { SummaryRow(summary: summary) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress-\(summary.exercise.name.text)")
          }
        }
        .padding(16)
      }
      .background(.surface)
      .navigationTitle("分析")
      .navigationDestination(for: ExerciseID.self) { id in
        ExerciseProgressScreen(exerciseID: id)
      }
    }
  }
}

private struct SummaryRow: View {
  let summary: ExerciseSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(summary.exercise.name.text, systemImage: "dumbbell").font(.body.weight(.bold))
      if let best = summary.best {
        Text("\(Format.scoreName(best.score.kind)) \(Format.score(best.score))")
          .font(.subheadline)
      }
      Text("最後の記録 \(Format.longDay(summary.lastDay))").font(.subheadline)
    }
  }
}

/// A bar for each of the last weeks, with the two latest weeks also written out.
private struct WeeklyBlock: View {
  let weeks: [WeekCount]

  private var headline: String {
    let latest = weeks.suffix(2).map(\.days)
    guard let thisWeek = latest.last else { return "" }
    guard latest.count == 2, let lastWeek = latest.first else { return "今週\(thisWeek)日" }
    return "今週\(thisWeek)日、先週\(lastWeek)日"
  }

  /// Every third week counted back from the current one, so the labels never touch.
  private var labelled: [String] {
    weeks.enumerated().filter { ($0.offset - (weeks.count - 1)) % 3 == 0 }
      .map { Format.axisDay($0.element.start) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GroupHeading(text: "週ごとのトレーニング日数", icon: "calendar")
      Text(headline).font(.title2.bold()).accessibilityIdentifier("weekly-headline")
      Chart {
        ForEach(weeks) { week in
          BarMark(
            x: .value("週の始まり", Format.axisDay(week.start)), y: .value("日数", week.days),
            width: .ratio(0.6)
          )
          .foregroundStyle(.ink)
          .accessibilityLabel("\(Format.shortDay(week.start))からの週")
          .accessibilityValue("\(week.days)日")
        }
        RuleMark(y: .value("日数", 0))
          .foregroundStyle(.ink)
          .lineStyle(StrokeStyle(lineWidth: 1))
          .accessibilityHidden(true)
      }
      .chartYScale(domain: 0...7)
      .chartYAxis {
        AxisMarks(position: .leading, values: [0, 1, 2, 3, 4, 5, 6, 7]) {
          AxisValueLabel().foregroundStyle(.ink)
        }
      }
      .chartXAxis {
        AxisMarks { value in
          if let label = value.as(String.self), labelled.contains(label) {
            AxisValueLabel().foregroundStyle(.ink)
          }
        }
      }
      .frame(height: 200)
      .accessibilityIdentifier("weekly-chart")
      Text("月曜日から日曜日までを1週間として、セットを記録した日を数えます。横軸は週の始まりの日付です。")
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private enum ProgressRange: CaseIterable {
  case threeMonths
  case year
  case all

  var title: String {
    switch self {
    case .threeMonths: "3か月"
    case .year: "1年"
    case .all: "すべて"
    }
  }

  func start(from today: LocalDay) -> LocalDay? {
    switch self {
    case .threeMonths: today.adding(days: -91) ?? .earliest
    case .year: today.adding(days: -365) ?? .earliest
    case .all: nil
    }
  }
}

/// One exercise's best score of each day as a line, with its personal bests and every session.
struct ExerciseProgressScreen: View {
  let exerciseID: ExerciseID
  @Environment(AppModel.self) private var model
  @State private var range = ProgressRange.threeMonths

  var body: some View {
    ScrollView {
      if let progress = model.log.progress(of: exerciseID) {
        VStack(alignment: .leading, spacing: 24) {
          BestBlock(progress: progress)
          Rule()
          chartBlock(progress)
          Rule()
          SessionsBlock(sessions: progress.sessions)
        }
        .padding(16)
      } else {
        Text("種目が見つかりません。分析の一覧に戻って選び直してください。").padding(16)
      }
    }
    .background(.surface)
    .navigationTitle(model.log.exercise(exerciseID)?.name.text ?? "種目")
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private func chartBlock(_ progress: ExerciseProgress) -> some View {
    let points = progress.points(since: range.start(from: model.today))
    let name = Format.scoreName(progress.kind)
    VStack(alignment: .leading, spacing: 12) {
      GroupHeading(text: "\(name)の推移", icon: "chart.xyaxis.line")
      HStack(spacing: 8) {
        ForEach(ProgressRange.allCases, id: \.self) { option in
          Button {
            range = option
          } label: {
            Label(option.title, systemImage: "calendar")
          }
          .buttonStyle(MonoButtonStyle(prominent: option == range))
          .accessibilityAddTraits(option == range ? .isSelected : [])
        }
      }
      if points.isEmpty {
        Text("選んだ期間に記録がありません。期間を広げてください。")
          .accessibilityIdentifier("empty-range")
      } else {
        ProgressChart(points: points, name: name)
      }
      if progress.kind == .oneRepMax {
        Text("推定1RMは、1回だけ挙げられる重量を、重量と回数から見積もった目安です。日ごとの最高値を表示します。")
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("重量を付けない種目は、1セットの最高回数を日ごとに表示します。")
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct ProgressChart: View {
  let points: [ProgressPoint]
  let name: String

  private static let axisStyle: Date.FormatStyle = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return Date.FormatStyle(
      date: .omitted, time: .omitted, locale: Locale(identifier: "ja_JP"), calendar: calendar,
      timeZone: .gmt
    )
    .month(.defaultDigits).day()
  }()

  var body: some View {
    Chart(points) { point in
      LineMark(x: .value("日付", point.day.noonUTC), y: .value(name, point.score.value))
        .foregroundStyle(.ink)
        .lineStyle(StrokeStyle(lineWidth: 2))
        .accessibilityHidden(true)
      PointMark(x: .value("日付", point.day.noonUTC), y: .value(name, point.score.value))
        .foregroundStyle(.ink)
        .symbolSize(64)
        .accessibilityLabel(Format.longDay(point.day))
        .accessibilityValue(Format.score(point.score))
    }
    .chartYScale(domain: .automatic(includesZero: false))
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) {
        AxisValueLabel(format: Self.axisStyle).foregroundStyle(.ink)
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
        AxisValueLabel().foregroundStyle(.ink)
      }
    }
    .environment(\.timeZone, .gmt)
    .frame(height: 220)
    .accessibilityIdentifier("progress-chart")
  }
}

private struct BestBlock: View {
  let progress: ExerciseProgress

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      GroupHeading(text: "自己ベスト", icon: "trophy")
      if let best = progress.best {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(Format.scoreName(progress.kind)) \(Format.score(best.score))")
            .font(.title2.bold())
            .accessibilityIdentifier("best-score")
          Text("\(Format.set(best.best))　\(Format.longDay(best.day))").font(.subheadline)
        }
      } else {
        Text("セットを記録すると、自己ベストを表示します。")
      }
      if let heaviest = progress.heaviest {
        VStack(alignment: .leading, spacing: 2) {
          Text("最大重量 \(Format.load(heaviest.weight))").font(.title3.bold())
          Text("\(Format.set(heaviest))　\(Format.longDay(heaviest.day))").font(.subheadline)
        }
      }
    }
  }
}

private struct SessionsBlock: View {
  let sessions: [Session]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      GroupHeading(text: "日ごとのセット", icon: "list.bullet")
      ForEach(sessions) { session in
        VStack(alignment: .leading, spacing: 2) {
          Text(Format.longDay(session.day)).font(.subheadline.weight(.bold))
          Text(session.sets.map(Format.set).joined(separator: "、"))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}
