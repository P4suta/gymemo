import Combine
import GymemoCopy
import GymemoCore
import GymemoKit
import SwiftUI

#if os(iOS) || os(visionOS)
  import AppIntents
#endif

@main
struct GymemoApp: App {
  @State private var launch = Launch.start(.current)

  init() {
    #if os(iOS) || os(visionOS)
      GymemoShortcuts.updateAppShortcutParameters()
    #endif
  }

  var body: some Scene {
    WindowGroup {
      switch launch {
      case .ready(let model):
        #if os(iOS)
          if LaunchConfiguration.current.usesAssistiveInterface {
            AssistiveLogScreen().environment(model)
          } else {
            RootView().environment(model)
          }
        #else
          RootView().environment(model)
        #endif
      case .failed(let failure): LaunchFailureScreen(failure: failure)
      }
    }
    #if os(macOS) || os(visionOS)
      .defaultSize(width: 1120, height: 760)
    #endif
    #if os(macOS)
      .commands {
        SidebarCommands()
        GymemoNavigationCommands()
      }
    #endif
    #if os(iOS)
      AssistiveAccess {
        switch launch {
        case .ready(let model): AssistiveLogScreen().environment(model)
        case .failed(let failure): LaunchFailureScreen(failure: failure)
        }
      }
    #endif
  }
}

struct RootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.appearsActive) private var appearsActive
  @Environment(\.scenePhase) private var scenePhase
  @State private var tab = LaunchConfiguration.current.initialTab
  @State private var drafts = LogDrafts()

  var body: some View {
    navigation
      .environment(drafts)
      .onOpenURL { url in
        if AppLink(url: url) == .log { tab = .log }
      }
      .handlesExternalEvents(preferring: appearsActive ? ["*"] : [], allowing: ["*"])
      #if os(macOS)
        .focusedSceneValue(\.gymemoTab, $tab)
      #endif
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { model.refreshToday() }
      }
      .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
        model.refreshToday()
      }
      .storageFailureAlert()
  }

  @ViewBuilder
  private var navigation: some View {
    #if os(macOS)
      MacNavigation(tab: $tab)
    #else
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
      .tabViewStyle(.sidebarAdaptable)
    #endif
  }
}

#if os(macOS)
  private struct GymemoTabKey: FocusedValueKey {
    typealias Value = Binding<RootTab>
  }

  extension FocusedValues {
    fileprivate var gymemoTab: Binding<RootTab>? {
      get { self[GymemoTabKey.self] }
      set { self[GymemoTabKey.self] = newValue }
    }
  }

  private struct GymemoNavigationCommands: Commands {
    @FocusedBinding(\.gymemoTab) private var tab

    var body: some Commands {
      CommandGroup(after: .sidebar) {
        Button(copy[.tabLog]) { tab = .log }.keyboardShortcut("1")
        Button(copy[.tabHistory]) { tab = .history }.keyboardShortcut("2")
        Button(copy[.tabAnalysis]) { tab = .analysis }.keyboardShortcut("3")
        Button(copy[.tabSettings]) { tab = .settings }.keyboardShortcut("4")
      }
    }
  }
#endif

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
