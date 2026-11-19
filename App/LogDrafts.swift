import GymemoCore
import Observation

struct LogSetDraft {
  var weightText: String
  var repsText: String
  let weightUnit: WeightUnit
  var storedWeight: Weight?
  var problem: String?
}

@MainActor
@Observable
final class LogDrafts {
  private struct Key: Hashable {
    let day: LocalDay
    let exercise: ExerciseID
  }

  private var entries: [Key: LogSetDraft] = [:]
  private var pending: [LocalDay: [ExerciseID]] = [:]

  func entry(
    for exercise: ExerciseID, on day: LocalDay, suggestion: SetEntry?, unit: WeightUnit
  ) -> LogSetDraft {
    entries[Key(day: day, exercise: exercise)]
      ?? LogSetDraft(
        weightText: suggestion.map { copy.using(weightUnit: unit).weightField($0.weight) } ?? "",
        repsText: suggestion.map { "\($0.reps.count)" } ?? "", weightUnit: unit,
        storedWeight: suggestion?.weight, problem: nil)
  }

  func update(_ draft: LogSetDraft, for exercise: ExerciseID, on day: LocalDay) {
    entries[Key(day: day, exercise: exercise)] = draft
  }

  func saved(_ entry: SetEntry, for exercise: ExerciseID, on day: LocalDay, unit: WeightUnit) {
    update(
      LogSetDraft(
        weightText: copy.using(weightUnit: unit).weightField(entry.weight),
        repsText: "\(entry.reps.count)", weightUnit: unit, storedWeight: entry.weight, problem: nil),
      for: exercise, on: day)
  }

  func waiting(on day: LocalDay) -> [ExerciseID] {
    pending[day] ?? []
  }

  func add(_ exercise: ExerciseID, on day: LocalDay) {
    if !waiting(on: day).contains(exercise) {
      pending[day, default: []].append(exercise)
    }
  }
}
