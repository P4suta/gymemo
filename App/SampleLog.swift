#if DEBUG
  import Foundation
  import GymemoCore

  /// Eight weeks of training that end on a given day, for UI tests and screenshots.
  /// The same day always gives the same log.
  enum SampleLog {
    private struct Plan {
      let weekday: Int
      let exercise: String
      let start: Int
      let step: Int
      let reps: [Int]
    }

    private static let plans = [
      Plan(weekday: 0, exercise: "ベンチプレス", start: 5500, step: 125, reps: [8, 8, 6]),
      Plan(weekday: 0, exercise: "懸垂", start: 0, step: 0, reps: [6, 5]),
      Plan(weekday: 2, exercise: "スクワット", start: 8000, step: 250, reps: [5, 5, 5]),
      Plan(weekday: 2, exercise: "ショルダープレス", start: 3000, step: 125, reps: [10, 8]),
      Plan(weekday: 4, exercise: "デッドリフト", start: 10_000, step: 500, reps: [5, 3]),
      Plan(weekday: 4, exercise: "ラットプルダウン", start: 4500, step: 125, reps: [10, 10, 8]),
    ]

    static func make(endingOn today: LocalDay) -> TrainingLog {
      var log = TrainingLog.starter
      var counter: UInt32 = 0
      for week in 0..<8 {
        for plan in plans {
          guard let day = today.weekStart.adding(days: (week - 7) * 7 + plan.weekday), day <= today,
            let exercise = log.exercises.first(where: { $0.name.text == plan.exercise }),
            let weight = Weight(hundredths: plan.start + plan.step * week)
          else { continue }
          for (index, count) in plan.reps.enumerated() {
            counter += 1
            let extra = weight.isBodyweight ? week / 2 : 0
            guard let reps = Reps(count + extra - (index == 2 && week == 3 ? 1 : 0)) else {
              continue
            }
            let command = Command.logSet(
              id: SetID(identifier(counter)), exerciseID: exercise.id, day: day, weight: weight,
              reps: reps)
            if case .success(let transition) = log.apply(command) { log = transition.log }
          }
        }
      }
      if let memoDay = today.adding(days: -5),
        case .success(let transition) = log.apply(.writeMemo(day: memoDay, text: "肩に違和感。重量は据え置き。"))
      {
        log = transition.log
      }
      return log
    }

    private static func identifier(_ number: UInt32) -> UUID {
      let bytes = withUnsafeBytes(of: number.bigEndian, Array.init)
      return UUID(
        uuid: (
          0x67, 0x79, 0x6D, 0x65, 0x6D, 0x6F, 0x40, 0x00, 0x80, 0x00, 0x53, 0x41,
          bytes[0], bytes[1], bytes[2], bytes[3]
        ))
    }
  }
#endif
