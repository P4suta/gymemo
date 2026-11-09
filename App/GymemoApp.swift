import Combine
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
      Tab("記録", systemImage: "square.and.pencil", value: RootTab.log) {
        NavigationStack {
          DayScreen(day: model.today).id(model.today)
        }
      }
      Tab("履歴", systemImage: "calendar", value: RootTab.history) {
        NavigationStack {
          HistoryScreen { tab = .log }
        }
      }
      Tab("分析", systemImage: "chart.xyaxis.line", value: RootTab.analysis) {
        NavigationStack {
          AnalysisScreen { tab = .log }
        }
      }
      Tab("設定", systemImage: "gearshape", value: RootTab.settings) {
        NavigationStack {
          SettingsScreen()
        }
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { model.refreshToday() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
      model.refreshToday()
    }
    .alert(
      "保存できませんでした", isPresented: Binding(isPresent: $model.storeFailure),
      presenting: model.storeFailure
    ) { _ in
      Button("閉じる", role: .cancel) {}
    } message: { failure in
      Text("記録は変わっていません。もう一度試してください。（コード \(failure.code)）")
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
      "新しいバージョンのアプリで作られた記録です。アプリを更新してから開いてください。"
    case .location:
      "記録を保存する場所を用意できませんでした。iPhoneの空き容量を確かめてから、もう一度開いてください。"
    case .store:
      "記録のファイルは消していません。アプリを終了して、もう一度開いてください。"
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
      Label("記録を開けませんでした", systemImage: "exclamationmark.triangle")
        .font(.title2.bold())
        .accessibilityAddTraits(.isHeader)
      Text(explanation)
      Text("コード \(code)").font(.subheadline.monospacedDigit())
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.surface)
  }
}
