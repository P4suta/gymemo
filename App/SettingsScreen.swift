import GymemoCopy
import GymemoCore
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsRoute: Hashable {
  case exercises
  case backup
}

struct SettingsScreen: View {
  private var version: String {
    let info = Bundle.main.infoDictionary
    return copy.version(
      marketing: info?["CFBundleShortVersionString"] as? String ?? "",
      build: info?["CFBundleVersion"] as? String ?? "")
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          NavigationLink(value: SettingsRoute.exercises) {
            LinkRow { Label(copy[.exercises], systemImage: "dumbbell") }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("open-exercises")
          NavigationLink(value: SettingsRoute.backup) {
            LinkRow { Label(copy[.exportAndImport], systemImage: "externaldrive") }
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("open-backup")
          VStack(alignment: .leading, spacing: 8) {
            GroupHeading(text: copy[.storageHeading], icon: "iphone")
            Text(copy[.storageText]).fixedSize(horizontal: false, vertical: true)
            Text(version).font(.subheadline)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.top, 32)
        }
        .padding(16)
      }
      .screenSurface()
      .navigationTitle(copy[.tabSettings])
      .navigationDestination(for: SettingsRoute.self) { route in
        switch route {
        case .exercises: ExerciseListScreen()
        case .backup: BackupScreen()
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
  @State private var export: Export?
  @State private var isImporting = false
  @State private var replacement: TrainingLog?
  @State private var notice: String?

  private struct Export {
    let document: ExportDocument
    let type: UTType
    let name: String
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let notice {
          Label(notice, systemImage: "info.circle")
            .font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("backup-notice")
        }
        section(
          title: copy[.exportBackup], icon: "square.and.arrow.up", text: copy[.exportBackupText],
          identifier: "export-backup"
        ) {
          export = Export(
            document: ExportDocument(data: Backup.write(model.log)), type: .json,
            name: "gymemo-backup-\(model.today.iso)")
        }
        Rule()
        section(
          title: copy[.exportCSV], icon: "tablecells", text: copy[.exportCSVText],
          identifier: "export-csv"
        ) {
          export = Export(
            document: ExportDocument(data: CSVExport.write(model.log, labels: copy.csvLabels)),
            type: .commaSeparatedText, name: "gymemo-\(model.today.iso)")
        }
        Rule()
        section(
          title: copy[.importBackup], icon: "square.and.arrow.down", text: copy[.importBackupText],
          identifier: "import-backup"
        ) {
          isImporting = true
        }
      }
      .padding(16)
    }
    .screenSurface()
    .navigationTitle(copy[.exportAndImport])
    .navigationBarTitleDisplayMode(.inline)
    .fileExporter(
      isPresented: Binding(isPresent: $export), document: export?.document,
      contentType: export?.type ?? .json, defaultFilename: export?.name
    ) { result in
      notice =
        switch result {
        case .success: copy[.exported]
        case .failure: copy[.exportFailed]
        }
    }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
      read(result)
    }
    .alert(
      copy[.replaceQuestion], isPresented: Binding(isPresent: $replacement), presenting: replacement
    ) { log in
      Button(copy[.replace], role: .destructive) {
        if model.perform(.replaceAll(log)) == .done { notice = copy[.imported] }
      }
      Button(copy[.cancel], role: .cancel) {}
    } message: { log in
      Text(copy.replaceMessage(current: model.log.sets.count, incoming: log.sets.count))
    }
  }

  private func section(
    title: String, icon: String, text: String, identifier: String, action: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(text).fixedSize(horizontal: false, vertical: true)
      Button(action: action) {
        Label(title, systemImage: icon)
      }
      .buttonStyle(MonoButtonStyle())
      .accessibilityIdentifier(identifier)
    }
  }

  private func read(_ result: Result<URL, any Error>) {
    guard case .success(let url) = result, url.startAccessingSecurityScopedResource() else {
      notice = copy[.fileUnreadable]
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }
    let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard size.map({ $0 <= Backup.maximumBytes }) ?? true else {
      notice = copy.problem(backup: .tooLarge)
      return
    }
    guard let data = try? Data(contentsOf: url) else {
      notice = copy[.fileUnreadable]
      return
    }
    switch Backup.read(data) {
    case .success(let log):
      notice = nil
      replacement = log
    case .failure(let refusal):
      notice = copy.problem(backup: refusal)
    }
  }
}
