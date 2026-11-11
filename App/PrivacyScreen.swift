import GymemoCopy
import SwiftUI

struct PrivacyScreen: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        section(.privacyCollection) {
          Text(copy[.privacyCollectionText])
            .accessibilityIdentifier("privacy-collection-value")
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("privacy-collection")
        section(.privacyOnDevice) {
          Text(copy[.privacyOnDeviceText])
            .accessibilityIdentifier("privacy-retention")
          Text(copy[.privacyWatchText])
            .accessibilityIdentifier("privacy-watch")
          Text(copy[.privacySyncText])
            .accessibilityIdentifier("privacy-sync")
          Text(copy[.privacyBackupText])
            .accessibilityIdentifier("privacy-backup")
        }
        section(.privacyFiles) {
          Text(copy[.privacyFilesText])
            .accessibilityIdentifier("privacy-files")
        }
        section(.privacyDeletion) {
          Text(copy[.privacyDeletionText])
            .accessibilityIdentifier("privacy-deletion")
          Text(copy[.privacyEraseText])
            .accessibilityIdentifier("privacy-erase-devices")
          Text(copy[.privacyCopiesText])
            .accessibilityIdentifier("privacy-delete-copies")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    #if os(iOS)
      .scrollEdgeEffectStyle(.hard, for: .top)
    #endif
    .navigationTitle(copy[.privacyPolicy])
    #if !os(watchOS)
      .toolbarTitleDisplayMode(.inline)
    #endif
  }

  private func section<Content: View>(
    _ title: CopyKey, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading) {
      Text(copy[title])
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
  }
}
