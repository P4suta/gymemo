import Combine
import GymemoCopy
import GymemoCore
import GymemoKit
import SwiftUI

@main
struct GymemoApp: App {
  @State private var launch = Launch.start(.current)

  var body: some Scene {
    WindowGroup {
      switch launch {
      case .ready(let model): RootView().environment(model)
      case .failed(let failure): LaunchFailureScreen(failure: failure)
      }
    }
  }
}

struct RootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @State private var tab = LaunchConfiguration.current.initialTab

  var body: some View {
    @Bindable var model = model
    TabView(selection: $tab) {
      Tab(copy[.tabLog], systemImage: "dumbbell.fill", value: RootTab.log) {
        NavigationStack {
          DayScreen(day: model.today).id(model.today)
        }
      }
      Tab(copy[.tabHistory], systemImage: "clock.fill", value: RootTab.history) {
        HistoryScreen { tab = .log }
      }
      Tab(copy[.tabAnalysis], systemImage: "chart.bar.fill", value: RootTab.analysis) {
        AnalysisScreen { tab = .log }
      }
      Tab(copy[.tabSettings], systemImage: "gearshape.fill", value: RootTab.settings) {
        SettingsScreen()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refreshToday() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      model.refreshToday()
    }
    .alert(
      copy[.saveFailed], isPresented: Binding(isPresent: $model.storeFailure),
      presenting: model.storeFailure
    ) { _ in
      // The system adds its own confirming button to an alert without actions.
    } message: { failure in
      Text(copy.saveFailedMessage(code: failure.code))
    }
  }
}

extension Binding where Value == Bool {
  /// True while `value` holds something, and setting it to false clears the value.
  init<Wrapped: Sendable>(isPresent value: Binding<Wrapped?>) {
    self.init(
      get: { value.wrappedValue != nil },
      set: { isPresent in
        if !isPresent { value.wrappedValue = nil }
      })
  }
}

struct LaunchFailureScreen: View {
  let failure: LaunchFailure

  private var explanation: String {
    switch failure {
    case .store(.unsupportedSchema(let version)) where version > TrainingLogStore.schemaVersion:
      copy[.launchNewer]
    case .location: copy[.launchLocation]
    case .store: copy[.launchStore]
    }
  }

  private var code: Int32 {
    switch failure {
    case .location: 0
    case .store(let failure): failure.code
    }
  }

  var body: some View {
    ContentUnavailableView {
      Label(copy[.launchFailed], systemImage: "exclamationmark.triangle")
    } description: {
      Text(explanation)
      Text(copy.failureCode(code))
    }
  }
}
