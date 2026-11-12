import GymemoCopy
import GymemoCore
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsRoute: Hashable {
  case exercises
  case backup
  case privacy
  case watch
}

struct SettingsScreen: View {
  @Environment(AppModel.self) private var model

  private var shortcutsURL: URL? {
    var components = URLComponents()
    components.scheme = "shortcuts"
    components.host = ""
    return components.url
  }

  private var version: String {
    let info = Bundle.main.infoDictionary
    return copy.version(
      marketing: info?["CFBundleShortVersionString"] as? String ?? "",
      build: info?["CFBundleVersion"] as? String ?? "")
  }

  var body: some View {
    let count = model.log.exercisesByBodyPart.reduce(0) { $0 + $1.exercises.count }
    NavigationStack {
      Form {
        Section {
          NavigationLink(value: SettingsRoute.exercises) {
            LabeledContent(copy[.exercises]) {
              Text(count.formatted(.number.locale(copy.locale)))
            }
          }
          .accessibilityIdentifier("open-exercises")
          NavigationLink(copy[.exportAndImport], value: SettingsRoute.backup)
            .accessibilityIdentifier("open-backup")
          #if os(iOS)
            NavigationLink(copy[.watch], value: SettingsRoute.watch)
              .accessibilityIdentifier("open-watch")
          #endif
          NavigationLink(copy[.privacyPolicy], value: SettingsRoute.privacy)
            .accessibilityIdentifier("open-privacy")
          #if os(iOS) || os(visionOS)
            if let shortcuts = shortcutsURL {
              Link(destination: shortcuts) {
                Text(copy[.shortcuts])
              }
              .accessibilityIdentifier("open-shortcuts")
            }
          #endif
        }
        Section {
          Text(copy[.storageText])
            .accessibilityIdentifier("storage-text")
        } header: {
          Text(copy[.storageHeading])
            .accessibilityIdentifier("storage-heading")
        } footer: {
          Text(version)
            .accessibilityLabel(copy[.versionLabel])
            .accessibilityValue(version)
            .accessibilityIdentifier("app-version")
        }
      }
      .formStyle(.grouped)
      .navigationLinkIndicatorVisibility(.visible)
      .navigationTitle(copy[.tabSettings])
      .navigationDestination(for: SettingsRoute.self) { route in
        switch route {
        case .exercises: ExerciseListScreen()
        case .backup: BackupScreen()
        case .privacy: PrivacyScreen()
        case .watch:
          List {
            Section { Text(copy[.watchHelp]) }
            Section(copy[.watchDelivery]) { Text(copy[.watchWaitingHint]) }
          }
          .navigationTitle(copy[.watch])
          .toolbarTitleDisplayMode(.inline)
        }
      }
    }
  }
}

/// A file that the lifter saves through the system's file picker.
struct ExportDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]

  let data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    guard let contents = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    data = contents
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

/// Writes the log to a JSON or CSV file, and replaces the log with a JSON backup.
struct BackupScreen: View {
  @Environment(AppModel.self) private var model
  @Environment(\.undoManager) private var undoManager
  @State private var export: Export?
  @State private var isExporting = false
  @State private var isImporting = false
  @State private var replacement: TrainingLog?
  @State private var notice: Notice?

  private struct Export {
    let document: ExportDocument
    let type: UTType
    let name: String
  }

  private struct Notice {
    let text: String
    let isFailure: Bool
  }

  var body: some View {
    List {
      if let notice {
        Section {
          NoticeRow(text: notice.text, isFailure: notice.isFailure)
            .accessibilityIdentifier("backup-notice")
        }
      }
      Section {
        Button(copy[.exportBackup], systemImage: "square.and.arrow.up") {
          export = Export(
            document: ExportDocument(data: Backup.write(model.log)), type: .json,
            name: "gymemo-backup-\(model.today.iso)")
          isExporting = true
        }
        .accessibilityIdentifier("export-backup")
      } footer: {
        Text(copy[.exportBackupText])
      }
      Section {
        Button(copy[.exportCSV], systemImage: "tablecells") {
          export = Export(
            document: ExportDocument(data: CSVExport.write(model.log, labels: copy.csvLabels)),
            type: .commaSeparatedText, name: "gymemo-\(model.today.iso)")
          isExporting = true
        }
        .accessibilityIdentifier("export-csv")
      } footer: {
        Text(copy[.exportCSVText])
      }
      Section {
        Button(copy[.importBackup], systemImage: "square.and.arrow.down") { isImporting = true }
          .accessibilityIdentifier("import-backup")
      } footer: {
        Text(copy[.importBackupText])
      }
    }
    .navigationTitle(copy[.exportAndImport])
    .toolbarTitleDisplayMode(.inline)
    .fileExporter(
      isPresented: $isExporting, document: export?.document,
      contentType: export?.type ?? .json, defaultFilename: export?.name
    ) { result in
      notice =
        switch result {
        case .success: Notice(text: copy[.exported], isFailure: false)
        case .failure: Notice(text: copy[.exportFailed], isFailure: true)
        }
      export = nil
    }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
      read(result)
    }
    .alert(
      copy[.replaceQuestion], isPresented: Binding(isPresent: $replacement), presenting: replacement
    ) { log in
      Button(copy[.replace], role: .destructive) {
        if model.perform(.replaceAll(log), undoManager: undoManager) == .done {
          notice = Notice(text: copy[.imported], isFailure: false)
        }
      }
      Button(copy[.cancel], role: .cancel) {}
    } message: { log in
      Text(copy.replaceMessage(current: model.log.sets.count, incoming: log.sets.count))
    }
  }

  private func fail(_ text: String) {
    notice = Notice(text: text, isFailure: true)
  }

  private func read(_ result: Result<URL, any Error>) {
    guard case .success(let url) = result, url.startAccessingSecurityScopedResource() else {
      fail(copy[.fileUnreadable])
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }
    let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard size.map({ $0 <= Backup.maximumBytes }) ?? true else {
      fail(copy.problem(backup: .tooLarge))
      return
    }
    guard let data = try? Data(contentsOf: url) else {
      fail(copy[.fileUnreadable])
      return
    }
    switch Backup.read(data) {
    case .success(let log):
      notice = nil
      replacement = log
    case .failure(let refusal):
      fail(copy.problem(backup: refusal))
    }
  }
}
