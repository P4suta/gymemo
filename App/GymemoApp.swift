import SwiftUI

@main
struct GymemoApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
        .tint(.ink)
    }
  }
}

struct RootView: View {
  var body: some View {
    Text("記録")
      .font(.largeTitle.bold())
      .foregroundStyle(.ink)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.surface)
  }
}
