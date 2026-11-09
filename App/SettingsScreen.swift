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
    let marketing = info?["CFBundleShortVersionString"] as? String ?? ""
    let build = info?["CFBundleVersion"] as? String ?? ""
    return "バージョン \(marketing)（\(build)）"
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          NavigationLink(value: SettingsRoute.exercises) {
            LinkRow { Label("種目の管理", systemImage: "dumbbell") }
          }
          .buttonStyle(.plain)
          NavigationLink(value: SettingsRoute.backup) {
            LinkRow { Label("書き出しと読み込み", systemImage: "externaldrive") }
          }
          .buttonStyle(.plain)
          VStack(alignment: .leading, spacing: 8) {
            GroupHeading(text: "記録の保存先", icon: "iphone")
            Text("記録はiPhoneの中だけに保存します。通信はしません。機種を変える前に、バックアップを書き出してください。")
              .fixedSize(horizontal: false, vertical: true)
            Text(version).font(.subheadline.monospacedDigit())
          }
          .padding(.top, 32)
        }
        .padding(16)
      }
      .background(.surface)
      .navigationTitle("設定")
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

  private static let csvLabels = CSVLabels(
    day: "日付", exercise: "種目", bodyPart: "部位", set: "セット", weight: "重量(kg)", reps: "回数",
    bodyParts: Dictionary(
      BodyPart.allCases.map { ($0, Format.bodyPart($0)) }, uniquingKeysWith: { first, _ in first })
  )

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
          title: "バックアップを書き出す", icon: "square.and.arrow.up",
          text: "すべての種目、セット、メモを1つのJSONファイルに保存します。機種を変える前に書き出してください。"
        ) {
          export = Export(
            document: ExportDocument(data: Backup.write(model.log)), type: .json,
            name: "gymemo-backup-\(model.today.iso)")
        }
        Rule()
        section(
          title: "CSVを書き出す", icon: "tablecells",
          text: "表計算アプリで開けるCSVファイルに、セットを1行ずつ保存します。CSVからは読み込めません。"
        ) {
          export = Export(
            document: ExportDocument(data: CSVExport.write(model.log, labels: Self.csvLabels)),
            type: .commaSeparatedText, name: "gymemo-\(model.today.iso)")
        }
        Rule()
        section(
          title: "バックアップを読み込む", icon: "square.and.arrow.down",
          text: "書き出したJSONファイルの内容で、今の記録をすべて置き換えます。置き換える前に確認します。"
        ) {
          isImporting = true
        }
      }
      .padding(16)
    }
    .background(.surface)
    .navigationTitle("書き出しと読み込み")
    .navigationBarTitleDisplayMode(.inline)
    .fileExporter(
      isPresented: Binding(isPresent: $export), document: export?.document,
      contentType: export?.type ?? .json, defaultFilename: export?.name
    ) { result in
      notice =
        switch result {
        case .success: "ファイルを書き出しました。"
        case .failure: "ファイルを書き出せませんでした。保存先を変えて、もう一度試してください。"
        }
    }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
      read(result)
    }
    .alert(
      "今の記録を置き換えますか", isPresented: Binding(isPresent: $replacement),
      presenting: replacement
    ) { log in
      Button("置き換える", role: .destructive) {
        if model.perform(.replaceAll(log)) == .done { notice = "バックアップを読み込みました。" }
      }
      Button("キャンセル", role: .cancel) {}
    } message: { log in
      Text(
        "今の\(model.log.sets.count)セットを消して、バックアップの\(log.sets.count)セットに置き換えます。置き換えた後は元に戻せません。"
      )
    }
  }

  private func section(
    title: String, icon: String, text: String, action: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(text).fixedSize(horizontal: false, vertical: true)
      Button(action: action) {
        Label(title, systemImage: icon)
      }
      .buttonStyle(MonoButtonStyle())
    }
  }

  private func read(_ result: Result<URL, any Error>) {
    let unreadable = "ファイルを開けませんでした。gymemoが書き出したJSONファイルを選んでください。"
    guard case .success(let url) = result, url.startAccessingSecurityScopedResource() else {
      notice = unreadable
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }
    let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    guard size.map({ $0 <= Backup.maximumBytes }) ?? true else {
      notice = Messages.backup(.tooLarge)
      return
    }
    guard let data = try? Data(contentsOf: url) else {
      notice = unreadable
      return
    }
    switch Backup.read(data) {
    case .success(let log):
      notice = nil
      replacement = log
    case .failure(let refusal):
      notice = Messages.backup(refusal)
    }
  }
}
