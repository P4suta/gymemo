import GymemoCopy
import SwiftUI

struct PrivacyScreen: View {
  var body: some View {
    List {
      Section {
        Text(copy[.privacyCollectionText])
          .accessibilityLabel(copy[.privacyCollection])
          .accessibilityValue(copy[.privacyCollectionText])
          .accessibilityIdentifier("privacy-collection")
      } header: {
        Text(copy[.privacyCollection])
      }
      Section {
        Text(copy[.privacyOnDeviceText])
      } header: {
        Text(copy[.privacyOnDevice])
      }
      Section {
        Text(copy[.privacyFilesText])
      } header: {
        Text(copy[.privacyFiles])
      }
      Section {
        Text(copy[.privacyDeletionText])
          .accessibilityIdentifier("privacy-deletion")
      } header: {
        Text(copy[.privacyDeletion])
      }
    }
    .navigationTitle(copy[.privacyPolicy])
    #if !os(watchOS)
      .toolbarTitleDisplayMode(.inline)
    #endif
  }
}
