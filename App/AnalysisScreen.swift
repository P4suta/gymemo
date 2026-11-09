import Charts
import GymemoCopy
import GymemoCore
import GymemoKit
import SwiftUI

/// The training days of recent weeks, and each exercise's progress.
struct AnalysisScreen: View {
  let openLog: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let summaries = model.log.exerciseSummaries
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          WeeklyBlock(weeks: model.log.weeklyTrainingDays(through: model.today, weeks: 12))
            .padding(.bottom, 24)
          Rule()
          GroupHeading(text: copy[.progressByExercise], icon: "chart.xyaxis.line")
            .padding(.top, 24)
            .padding(.bottom, 8)
          if summaries.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
              Text(copy[.analysisEmpty]).accessibilityIdentifier("empty-analysis")
              Button(action: openLog) {
                Label(copy[.startToday], systemImage: "square.and.pencil")
              }
              .buttonStyle(MonoButtonStyle(prominent: true))
              .accessibilityIdentifier("start-today")
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
      .screenSurface()
      .navigationTitle(copy[.tabAnalysis])
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
        Text(copy.scoreLine(best.score)).font(.subheadline)
      }
      Text(copy.lastLogged(summary.lastDay)).font(.subheadline)
    }
  }
}

/// A bar for each of the last weeks, with the two latest weeks also written out.
private struct WeeklyBlock: View {
  let weeks: [WeekCount]

  private var headline: String {
    let latest = weeks.suffix(2).map(\.days)
    guard let thisWeek = latest.last else { return "" }
    return copy.weeklyHeadline(thisWeek: thisWeek, lastWeek: latest.count == 2 ? latest.first : nil)
  }

  /// Every third week counted back from the current one, so the labels never touch.
  private var labelled: [String] {
    weeks.enumerated().filter { ($0.offset - (weeks.count - 1)) % 3 == 0 }
      .map { copy.day($0.element.start, .axis) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      GroupHeading(text: copy[.weeklyTrainingDays], icon: "calendar")
      Text(headline).font(.title2.bold()).accessibilityIdentifier("weekly-headline")
      Chart {
        ForEach(weeks) { week in
          BarMark(
            x: .value(copy[.axisWeekStart], copy.day(week.start, .axis)),
            y: .value(copy[.axisDays], week.days), width: .ratio(0.6)
          )
          .foregroundStyle(.ink)
          .accessibilityLabel(copy.weekLabel(startingOn: week.start))
          .accessibilityValue(copy.dayCount(week.days))
        }
        RuleMark(y: .value(copy[.axisDays], 0))
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
      Text(copy[.weeklyCaption])
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private enum ProgressRange: String, CaseIterable {
  case threeMonths
  case year
  case all

  var title: String {
    switch self {
    case .threeMonths: copy[.threeMonths]
    case .year: copy[.oneYear]
    case .all: copy[.allTime]
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        Text(copy[.exerciseMissing]).padding(16)
      }
    }
    .screenSurface()
    .navigationTitle(model.log.exercise(exerciseID)?.name.text ?? copy[.tabAnalysis])
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private func chartBlock(_ progress: ExerciseProgress) -> some View {
    let points = progress.points(since: range.start(from: model.today))
    VStack(alignment: .leading, spacing: 12) {
      GroupHeading(text: copy.progressHeading(progress.kind), icon: "chart.xyaxis.line")
      // At the accessibility sizes the three periods stack, so each label stays on one line.
      let layout =
        dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
      layout {
        ForEach(ProgressRange.allCases, id: \.self) { option in
          Button {
            range = option
          } label: {
            Label(option.title, systemImage: "calendar")
          }
          .buttonStyle(MonoButtonStyle(prominent: option == range))
          .accessibilityAddTraits(option == range ? .isSelected : [])
          .accessibilityIdentifier("range-\(option.rawValue)")
        }
      }
      if points.isEmpty {
        Text(copy[.emptyRange]).accessibilityIdentifier("empty-range")
      } else {
        ProgressChart(points: points, name: copy.scoreName(progress.kind))
      }
      Text(progress.kind == .oneRepMax ? copy[.oneRepMaxNote] : copy[.repsNote])
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct ProgressChart: View {
  let points: [ProgressPoint]
  let name: String

  var body: some View {
    Chart(points) { point in
      LineMark(x: .value(copy[.axisDate], point.day.noonUTC), y: .value(name, point.score.value))
        .foregroundStyle(.ink)
        .lineStyle(StrokeStyle(lineWidth: 2))
        .accessibilityHidden(true)
      PointMark(x: .value(copy[.axisDate], point.day.noonUTC), y: .value(name, point.score.value))
        .foregroundStyle(.ink)
        .symbolSize(64)
        .accessibilityLabel(copy.day(point.day, .long))
        .accessibilityValue(copy.score(point.score))
    }
    .chartYScale(domain: .automatic(includesZero: false))
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) {
        AxisValueLabel(format: copy.dateStyle(.axis)).foregroundStyle(.ink)
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
        AxisValueLabel().foregroundStyle(.ink)
      }
    }
    .environment(\.timeZone, .gmt)
    .environment(\.calendar, copy.calendar)
    .frame(height: 220)
    .accessibilityIdentifier("progress-chart")
  }
}

private struct BestBlock: View {
  let progress: ExerciseProgress

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      GroupHeading(text: copy[.personalBest], icon: "trophy")
      if let best = progress.best {
        VStack(alignment: .leading, spacing: 2) {
          Text(copy.scoreLine(best.score))
            .font(.title2.bold())
            .accessibilityIdentifier("best-score")
          Text(copy.setOnDay(weight: best.best.weight, reps: best.best.reps, day: best.day))
            .font(.subheadline)
        }
      } else {
        Text(copy[.personalBestEmpty])
      }
      if let heaviest = progress.heaviest {
        VStack(alignment: .leading, spacing: 2) {
          Text(copy.heaviest(heaviest.weight)).font(.title3.bold())
          Text(copy.setOnDay(weight: heaviest.weight, reps: heaviest.reps, day: heaviest.day))
            .font(.subheadline)
        }
      }
    }
  }
}

private struct SessionsBlock: View {
  let sessions: [Session]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      GroupHeading(text: copy[.setsByDay], icon: "list.bullet")
      ForEach(sessions) { session in
        VStack(alignment: .leading, spacing: 2) {
          Text(copy.day(session.day, .long)).font(.subheadline.weight(.bold))
          Text(copy.sets(session.sets)).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}
