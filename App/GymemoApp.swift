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
      Group {
        switch launch {
        case .ready(let model): RootView().environment(model)
        case .failed(let failure): LaunchFailureScreen(failure: failure)
        }
      }
      .tint(.ink)
      .foregroundStyle(.ink)
      .background(.surface)
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
      Tab(copy[.tabLog], systemImage: "square.and.pencil", value: RootTab.log) {
        NavigationStack {
          DayScreen(day: model.today).id(model.today)
        }
      }
      Tab(copy[.tabHistory], systemImage: "calendar", value: RootTab.history) {
        HistoryScreen { tab = .log }
      }
      Tab(copy[.tabAnalysis], systemImage: "chart.xyaxis.line", value: RootTab.analysis) {
        AnalysisScreen { tab = .log }
      }
      Tab(copy[.tabSettings], systemImage: "gearshape", value: RootTab.settings) {
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
      Button(copy[.close], role: .cancel) {}
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
    VStack(alignment: .leading, spacing: 16) {
      Label(copy[.launchFailed], systemImage: "exclamationmark.triangle")
        .font(.title2.bold())
        .accessibilityAddTraits(.isHeader)
      Text(explanation)
      Text(copy.failureCode(code)).font(.subheadline)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.surface)
  }
}
