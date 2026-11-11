import Foundation
import GymemoCore

/// Watch state changes become visible only after an atomic file replacement succeeds.
@MainActor
public final class CompanionJournal {
  public static let maximumEntries = CompanionQueue.maximumEntries
  public var entries: [CompanionQueuedSet] { queue.entries }
  public private(set) var catalog = CompanionCatalog(log: .empty)
  private var queue = CompanionQueue()
  private let url: URL

  private struct Snapshot: Codable {
    let version: Int
    let catalog: Data
    let entries: [EntryRecord]
  }

  private struct EntryRecord: Codable {
    let message: Data
    let name: String?
  }

  public init(url: URL) throws(CompanionFailure) {
    self.url = url
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let data: Data
    do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch {
      throw .file(operation: .read, code: (error as NSError).code)
    }
    guard data.count <= 2_000_000,
      let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.version == 1,
      snapshot.entries.count <= Self.maximumEntries,
      case .catalog(let catalog) = try CompanionCodec.decode(snapshot.catalog)
    else { throw .malformed }
    var entries: [CompanionQueuedSet] = []
    for encoded in snapshot.entries {
      let name: ExerciseName?
      if let text = encoded.name {
        guard case .success(let parsed) = ExerciseName.parse(text) else { throw .malformed }
        name = parsed
      } else {
        name = nil
      }
      switch try CompanionCodec.decode(encoded.message) {
      case .entry(let set):
        entries.append(CompanionQueuedSet(set: set, outcome: nil, exerciseName: name))
      case .receipt(let receipt):
        entries.append(
          CompanionQueuedSet(set: receipt.set, outcome: receipt.outcome, exerciseName: name))
      case .catalog: throw .malformed
      }
    }
    guard let queue = CompanionQueue(entries: entries) else { throw .duplicateIdentifier }
    self.catalog = catalog
    self.queue = queue
  }

  public func update(_ catalog: CompanionCatalog) throws(CompanionFailure) {
    try persist(queue: queue, catalog: catalog)
  }

  public func enqueue(_ set: LoggedSet) throws(CompanionFailure) {
    let name = catalog.exercises.first { $0.id == set.exerciseID }?.exercise.name
    switch queue.enqueue(set, name: name) {
    case .success(let changed): try persist(queue: changed, catalog: catalog)
    case .failure(.duplicateIdentifier): throw .duplicateIdentifier
    case .failure(.full): throw .queueFull
    }
  }

  public func acknowledge(_ receipt: CompanionReceipt) throws(CompanionFailure) {
    let changed = queue.acknowledging(receipt)
    if changed != queue { try persist(queue: changed, catalog: catalog) }
  }

  public func retry(_ id: SetID) throws(CompanionFailure) {
    let changed = queue.retrying(id)
    if changed != queue { try persist(queue: changed, catalog: catalog) }
  }

  private func persist(queue: CompanionQueue, catalog: CompanionCatalog) throws(CompanionFailure) {
    let encoded = try queue.entries.map { entry throws(CompanionFailure) in
      let message: CompanionMessage =
        entry.outcome.map {
          .receipt(CompanionReceipt(set: entry.set, outcome: $0))
        } ?? .entry(entry.set)
      return EntryRecord(
        message: try CompanionCodec.encode(message), name: entry.exerciseName?.text)
    }
    let snapshot = Snapshot(
      version: 1, catalog: try CompanionCodec.encode(.catalog(catalog)), entries: encoded)
    guard let data = try? JSONEncoder().encode(snapshot) else { throw .malformed }
    do { try data.write(to: url, options: .atomic) } catch {
      throw .file(operation: .write, code: (error as NSError).code)
    }
    self.queue = queue
    self.catalog = catalog
  }
}
