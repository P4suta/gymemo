import Foundation
import GymemoCopy
import GymemoCore
import GymemoKit
import Observation

@MainActor
@Observable
final class WatchModel {
  private(set) var catalog: CompanionCatalog
  private(set) var entries: [CompanionQueuedSet]
  var failure: String?
  @ObservationIgnored private let journal: CompanionJournal
  @ObservationIgnored private let companion: CompanionSession?
  @ObservationIgnored private var attempted: Set<SetID> = []

  init(journal: CompanionJournal, connectsToPhone: Bool) {
    self.journal = journal
    catalog = journal.catalog
    entries = journal.entries
    companion = connectsToPhone ? CompanionSession() : nil
    companion?.onMessage = { [weak self] message in self?.receive(message) }
    companion?.onActivation = { [weak self] in self?.resumeTransfers() }
    companion?.onDrain = { [weak self] in self?.flush() }
    companion?.onFailure = { [weak self] _ in self?.failure = copy[.watchTransferFailed] }
    companion?.start()
  }

  static func open() throws -> WatchModel {
    let manager = FileManager.default
    let directory = try manager.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var url = directory.appending(path: "watch-journal.json")
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      let isFixture = arguments.contains("-gymemo-watch-checks")
      if isFixture {
        url = directory.appending(path: "watch-checks.json")
        if arguments.contains("-gymemo-reset") && manager.fileExists(atPath: url.path) {
          try manager.removeItem(at: url)
        }
      }
    #else
      let isFixture = false
    #endif
    let journal = try CompanionJournal(url: url)
    #if DEBUG
      if isFixture { try journal.update(CompanionCatalog(log: .starter(named: copy.starterName))) }
    #endif
    return WatchModel(journal: journal, connectsToPhone: !isFixture)
  }

  @discardableResult
  func log(exercise: ExerciseID, weight: Weight, reps: Reps) -> SetID? {
    let set = LoggedSet(
      id: SetID(UUID()), exerciseID: exercise, day: LocalDay.nearest(to: Date(), in: .current),
      weight: weight, reps: reps)
    do {
      try journal.enqueue(set)
      entries = journal.entries
      failure = nil
      flush()
      return set.id
    } catch {
      failure = copy[.saveFailed]
      return nil
    }
  }

  func retry(_ id: SetID) {
    do {
      try journal.retry(id)
      entries = journal.entries
      attempted.remove(id)
      flush()
    } catch {
      failure = copy[.saveFailed]
    }
  }

  func resumeTransfers() {
    attempted.removeAll()
    flush()
  }

  func finishBackgroundDelivery() async {
    await companion?.finishBackgroundDelivery()
  }

  private func flush() {
    guard let companion else { return }
    let pending = entries.filter { $0.outcome == nil && !attempted.contains($0.id) }
    for entry in pending.prefix(20) {
      if companion.send(.entry(entry.set)) { attempted.insert(entry.id) }
    }
  }

  private func receive(_ message: CompanionMessage) {
    do {
      switch message {
      case .catalog(let catalog):
        try journal.update(catalog)
        self.catalog = journal.catalog
      case .receipt(let receipt):
        try journal.acknowledge(receipt)
        entries = journal.entries
        flush()
      case .entry: return
      }
    } catch {
      failure = copy[.saveFailed]
    }
  }
}
