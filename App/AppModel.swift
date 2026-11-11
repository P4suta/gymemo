import Foundation
import GymemoCopy
import GymemoCore
import GymemoKit
import Observation

enum PerformOutcome: Equatable {
  case done
  case refused(Refusal)
  case notStored
}

/// The log that every screen shows, which changes only after the store holds the change.
@MainActor
@Observable
final class AppModel {
  private(set) var log: TrainingLog
  private(set) var today: LocalDay
  var storeFailure: StoreFailure?
  @ObservationIgnored private let undoManagers = NSHashTable<UndoManager>.weakObjects()
  #if os(iOS)
    var companionFailure: CompanionTransferFailure?
    @ObservationIgnored private var companion: CompanionSession?
  #endif

  @ObservationIgnored private let store: TrainingLogStore
  @ObservationIgnored private let currentDay: () -> LocalDay

  init(
    store: TrainingLogStore, log: TrainingLog, currentDay: @escaping () -> LocalDay,
    connectsToWatch: Bool = true
  ) {
    self.store = store
    self.log = log
    self.currentDay = currentDay
    today = currentDay()
    #if os(iOS)
      if connectsToWatch && CompanionSession.isSupported {
        let companion = CompanionSession()
        self.companion = companion
        companion.onMessage = { [weak self] message in self?.receive(message) }
        companion.onActivation = { [weak self] in self?.publishToWatch() }
        companion.onFailure = { [weak self] failure in self?.companionFailure = failure }
        companion.start()
      }
    #endif
  }

  @discardableResult
  func perform(_ command: Command, undoManager: UndoManager? = nil) -> PerformOutcome {
    switch log.apply(command) {
    case .failure(let refusal):
      return .refused(refusal)
    case .success(let transition):
      let previous = log
      do {
        try store.apply(transition.changes)
      } catch {
        storeFailure = error
        return .notStored
      }
      log = transition.log
      if !transition.changes.isEmpty {
        invalidateUndo(except: undoManager)
        if let undoManager { remember(previous, action: actionName(command), in: undoManager) }
      }
      #if os(iOS)
        publishToWatch()
      #endif
      return .done
    }
  }

  func refreshToday() {
    let now = currentDay()
    if now != today { today = now }
  }

  func newExerciseID() -> ExerciseID {
    ExerciseID(UUID())
  }

  func newSetID() -> SetID {
    SetID(UUID())
  }

  private func actionName(_ command: Command) -> String {
    switch command {
    case .addExercise: copy[.newExercise]
    case .editExercise, .setExerciseArchived: copy[.editExercise]
    case .deleteExercise: copy[.deleteExercise]
    case .logSet: copy[.logSet]
    case .editSet: copy[.editSet]
    case .deleteSet: copy[.deleteSet]
    case .writeMemo: copy[.editNote]
    case .replaceAll: copy[.importBackup]
    }
  }

  private func invalidateUndo(except current: UndoManager? = nil) {
    for manager in undoManagers.allObjects where manager !== current { manager.removeAllActions() }
  }

  private func remember(_ previous: TrainingLog, action: String, in undoManager: UndoManager) {
    undoManagers.add(undoManager)
    let count = max(log.sets.count, previous.sets.count) + log.exercises.count + log.memos.count
    undoManager.levelsOfUndo = max(1, min(20, 50_000 / max(count, 1)))
    undoManager.registerUndo(withTarget: self) { [weak undoManager] target in
      MainActor.assumeIsolated {
        target.restore(previous, action: action, undoManager: undoManager)
      }
    }
    undoManager.setActionName(action)
  }

  private func restore(_ saved: TrainingLog, action: String, undoManager: UndoManager?) {
    do {
      try store.apply([.replaceAll(saved)])
      let previous = log
      log = saved
      invalidateUndo(except: undoManager)
      if let undoManager { remember(previous, action: action, in: undoManager) }
      #if os(iOS)
        publishToWatch()
      #endif
    } catch {
      storeFailure = error
    }
  }

  #if os(iOS)
    func publishToWatch() {
      companion?.publish(CompanionCatalog(log: log))
    }

    private func receive(_ message: CompanionMessage) {
      guard case .entry(let set) = message else { return }
      do {
        let received = try store.receive(set)
        if received.log != log { invalidateUndo() }
        log = received.log
        companion?.send(.receipt(received.receipt))
        publishToWatch()
      } catch {
        storeFailure = error
      }
    }
  #endif
}
