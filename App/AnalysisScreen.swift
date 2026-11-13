import Charts
import GymemoCopy
import GymemoCore
import GymemoKit
import SwiftUI

/// The training days of recent weeks, and each exercise's progress.
struct AnalysisScreen: View {
  let openLog: () -> Void
  @State private var selectedExercise: ExerciseID?

  var body: some View {
    NavigationSplitView {
      AnalysisList(selectedExercise: $selectedExercise, openLog: openLog)
    } detail: {
      AnalysisDetail(exerciseID: selectedExercise)
    }
    .navigationSplitViewStyle(.balanced)
  }
}

struct AnalysisDetail: View {
  let exerciseID: ExerciseID?

  var body: some View {
    if let exerciseID {
      ExerciseProgressScreen(exerciseID: exerciseID).id(exerciseID)
    } else {
      ContentUnavailableView(copy[.chooseExercise], systemImage: "chart.xyaxis.line")
    }
  }
}

struct AnalysisList: View {
  @Binding var selectedExercise: ExerciseID?
  let openLog: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let summaries = model.log.exerciseSummaries
    List(selection: $selectedExercise) {
      Section {
        WeeklyBlock(weeks: model.log.weeklyTrainingDays(through: model.today, weeks: 12))
        #if os(macOS)
          Text(copy[.weeklyCaption]).font(.footnote).foregroundStyle(SecondaryTextStyle())
            .fixedSize(horizontal: false, vertical: true)
        #endif
      } header: {
        Text(copy[.weeklyTrainingDays])
      } footer: {
        #if !os(macOS)
          Text(copy[.weeklyCaption])
        #endif
      }
      if summaries.isEmpty {
        Section {
          ContentUnavailableView {
            Label(copy[.analysisEmptyTitle], systemImage: "chart.bar")
              .accessibilityIdentifier("empty-analysis")
          } description: {
            Text(copy[.analysisEmpty])
          } actions: {
            Button(copy[.startToday], action: openLog)
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("start-today")
          }
        }
        .listRowBackground(Color.clear)
      } else {
        Section(copy[.progressByExercise]) {
          ForEach(summaries) { summary in
            NavigationLink(value: summary.exercise.id) {
              StackedRow(
                title: summary.exercise.name.text,
                subtitle: summary.best.map { copy.scoreLine($0.score) },
                caption: copy.lastLogged(summary.lastDay),
                isSelected: selectedExercise == summary.exercise.id)
            }
            .accessibilityIdentifier("progress-\(summary.exercise.name.text)")
          }
        }
      }
    }
    .navigationTitle(copy[.tabAnalysis])
    .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
    #if os(macOS)
      .listStyle(.inset)
    #endif
  }
}

/// A bar for each of the last weeks, under a sentence that states the two newest values.
/// The charting guidance asks for descriptive text beside a chart.
/// See https://developer.apple.com/design/human-interface-guidelines/charting-data.
private struct WeeklyBlock: View {
  let weeks: [WeekCount]
  @Environment(\.dynamicTypeSize) private var typeSize

  private var headline: String {
    let latest = weeks.suffix(2).map(\.days)
    guard let thisWeek = latest.last else { return "" }
    return copy.weeklyHeadline(thisWeek: thisWeek, lastWeek: latest.count == 2 ? latest.first : nil)
  }

  /// Every third week counted back from the current one, so the labels never touch.
  /// At the accessibility text sizes only the current week and the one in the middle keep a label, and a label under the first bar would leave the chart.
  private var labelled: [String] {
    let step = typeSize.isAccessibilitySize ? max(weeks.count / 2, 1) : 3
    return weeks.enumerated().filter { ($0.offset - (weeks.count - 1)) % step == 0 }
      .map { copy.day($0.element.start, .axis) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(headline).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("weekly-headline")
      Chart(weeks) { week in
        BarMark(
          x: .value(copy[.axisWeekStart], copy.day(week.start, .axis)),
          y: .value(copy[.axisDays], week.days), width: .ratio(0.6)
        )
        .foregroundStyle(.tint)
        .accessibilityLabel(copy.weekLabel(startingOn: week.start))
        .accessibilityValue(copy.dayCount(week.days))
      }
      .chartYScale(domain: 0...7)
      .chartXAxis {
        AxisMarks { value in
          if let label = value.as(String.self), labelled.contains(label) {
            AxisGridLine()
            AxisValueLabel()
          }
        }
      }
      .frame(height: 180)
      .accessibilityIdentifier("weekly-chart")
    }
    .padding(.vertical, 4)
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
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var range = ProgressRange.threeMonths

  var body: some View {
    List {
      if let progress = model.log.progress(of: exerciseID) {
        Section {
          rangePicker(title: copy.progressHeading(progress.kind))
          let points = progress.points(since: range.start(from: model.today))
          if points.isEmpty {
            ContentUnavailableView {
              Label(copy[.emptyRangeTitle], systemImage: "chart.xyaxis.line")
                .accessibilityIdentifier("empty-range")
            } description: {
              Text(copy[.emptyRange])
            }
          } else {
            ProgressChart(points: points, name: copy.scoreName(progress.kind))
          }
          #if os(macOS)
            Text(progress.kind == .oneRepMax ? copy[.oneRepMaxNote] : copy[.repsNote])
              .font(.footnote).foregroundStyle(SecondaryTextStyle())
              .fixedSize(horizontal: false, vertical: true)
          #endif
        } header: {
          Text(copy.progressHeading(progress.kind))
        } footer: {
          #if !os(macOS)
            Text(progress.kind == .oneRepMax ? copy[.oneRepMaxNote] : copy[.repsNote])
          #endif
        }
        Section(copy[.personalBest]) {
          BestRows(progress: progress)
        }
        Section(copy[.setsByDay]) {
          ForEach(progress.sessions) { session in
            StackedRow(overline: copy.day(session.day, .long), title: copy.sets(session.sets))
          }
        }
      } else {
        Text(copy[.exerciseMissing])
      }
    }
    .navigationTitle(model.log.exercise(exerciseID)?.name.text ?? copy[.tabAnalysis])
    .toolbarTitleDisplayMode(.inline)
  }

  /// The three ranges as a segmented control, or as a menu at the accessibility text sizes, where segment labels can't grow.
  /// The section header names the menu, so the menu shows its value alone.
  @ViewBuilder
  private func rangePicker(title: String) -> some View {
    let picker = Picker(title, selection: $range) {
      ForEach(ProgressRange.allCases, id: \.self) { option in
        Text(option.title).tag(option)
      }
    }
    .labelsHidden()
    .accessibilityIdentifier("range")
    if typeSize.isAccessibilitySize {
      picker.pickerStyle(.menu).labelsHidden()
    } else {
      picker.pickerStyle(.segmented)
    }
  }
}

private struct ProgressChart: View {
  let points: [ProgressPoint]
  let name: String
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    // Fewer dates fit under the chart at the accessibility text sizes.
    let dates = typeSize.isAccessibilitySize ? 2 : 4
    Chart(points) { point in
      LineMark(x: .value(copy[.axisDate], point.day.noonUTC), y: .value(name, point.score.value))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      PointMark(x: .value(copy[.axisDate], point.day.noonUTC), y: .value(name, point.score.value))
        .foregroundStyle(.tint)
        .accessibilityLabel(copy.day(point.day, .long))
        .accessibilityValue(copy.score(point.score))
    }
    .chartYScale(domain: .automatic(includesZero: false))
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: dates)) {
        AxisGridLine()
        AxisValueLabel(format: copy.dateStyle(.axis))
      }
    }
    .chartYAxis {
      AxisMarks(values: .automatic(desiredCount: 4))
    }
    .environment(\.timeZone, .gmt)
    .environment(\.calendar, copy.calendar)
    .frame(height: 200)
    .padding(.vertical, 4)
    .accessibilityIdentifier("progress-chart")
  }
}

private struct BestRows: View {
  let progress: ExerciseProgress

  var body: some View {
    if let best = progress.best {
      VStack(alignment: .leading, spacing: 2) {
        Text(copy.scoreLine(best.score)).font(.headline).accessibilityIdentifier("best-score")
        Text(copy.setOnDay(weight: best.best.weight, reps: best.best.reps, day: best.day))
          .font(.subheadline)
          .foregroundStyle(SecondaryTextStyle())
      }
    } else {
      Text(copy[.personalBestEmpty])
    }
    if let heaviest = progress.heaviest {
      StackedRow(
        title: copy.heaviest(heaviest.weight),
        subtitle: copy.setOnDay(weight: heaviest.weight, reps: heaviest.reps, day: heaviest.day),
        isEmphasized: true)
    }
  }
}
