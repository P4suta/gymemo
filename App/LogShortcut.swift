import AppIntents
import GymemoKit

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct OpenLogIntent: AppIntent {
  static let title: LocalizedStringResource = "openLog"
  static let supportedModes: IntentModes = .foreground

  @MainActor
  func perform() async throws -> some IntentResult {
    let url = try AppLink.log.url()
    #if os(macOS)
      _ = try await NSWorkspace.shared.open(
        [url], withApplicationAt: Bundle.main.bundleURL, configuration: .init())
    #else
      let opened = await UIApplication.shared.open(url)
      guard opened else { throw URLError(.unsupportedURL) }
    #endif
    return .result()
  }
}

#if os(iOS) || os(visionOS)
  struct GymemoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
      AppShortcut(
        intent: OpenLogIntent(),
        phrases: [
          "Open the log in \(.applicationName)",
          "Start a set in \(.applicationName)",
        ],
        shortTitle: "openLog", systemImageName: "dumbbell.fill")
    }
  }
#endif
