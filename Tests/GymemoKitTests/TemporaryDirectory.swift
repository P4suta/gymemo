import Foundation

/// A directory that one test owns and that disappears with the value.
final class TemporaryDirectory {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory.appending(
      path: "gymemo-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  func file(_ name: String) -> URL {
    url.appending(path: name, directoryHint: .notDirectory)
  }
}
