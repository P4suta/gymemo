import Foundation
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

  @ObservationIgnored private let store: TrainingLogStore
  @ObservationIgnored private let currentDay: () -> LocalDay

  init(store: TrainingLogStore, log: TrainingLog, currentDay: @escaping () -> LocalDay) {
    self.store = store
    self.log = log
    self.currentDay = currentDay
    today = currentDay()
  }

  @discardableResult
  func perform(_ command: Command) -> PerformOutcome {
    switch log.apply(command) {
    case .failure(let refusal):
      return .refused(refusal)
    case .success(let transition):
      do {
        try store.apply(transition.changes)
      } catch {
        storeFailure = error
        return .notStored
      }
      log = transition.log
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
}
