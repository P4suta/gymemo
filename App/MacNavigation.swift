#if os(macOS)
  import GymemoCopy
  import GymemoCore
  import SwiftUI

  struct MacNavigation: View {
    @Binding var tab: RootTab
    @Environment(AppModel.self) private var model
    @State private var selectedDay: LocalDay?
    @State private var selectedExercise: ExerciseID?

    var body: some View {
      switch tab {
      case .history:
        NavigationSplitView {
          sidebar
        } content: {
          HistoryList(selectedDay: $selectedDay, openLog: { tab = .log }) {
            selectedDay = $0
          }
        } detail: {
          HistoryDetail(day: selectedDay)
        }
      case .analysis:
        NavigationSplitView {
          sidebar
        } content: {
          AnalysisList(selectedExercise: $selectedExercise) { tab = .log }
        } detail: {
          AnalysisDetail(exerciseID: selectedExercise)
        }
      case .log, .settings:
        NavigationSplitView {
          sidebar
        } detail: {
          if tab == .log {
            NavigationStack {
              DayScreen(day: model.today).id(model.today)
            }
          } else {
            SettingsScreen()
          }
        }
      }
    }

    private var sidebar: some View {
      List(selection: $tab) {
        ForEach(RootTab.allCases, id: \.self) { area in
          Label(copy[area.title], systemImage: area.symbol).tag(area)
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 300)
    }
  }

  extension RootTab {
    fileprivate var title: CopyKey {
      switch self {
      case .log: .tabLog
      case .history: .tabHistory
      case .analysis: .tabAnalysis
      case .settings: .tabSettings
      }
    }

    fileprivate var symbol: String {
      switch self {
      case .log: "dumbbell.fill"
      case .history: "clock.fill"
      case .analysis: "chart.bar.fill"
      case .settings: "gearshape.fill"
      }
    }
  }
#endif
