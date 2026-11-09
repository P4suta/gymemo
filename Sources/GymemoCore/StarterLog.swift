import Foundation

/// An exercise that a new installation offers before the lifter adds any.
/// The raw value is part of the exercise's identifier, so a new case takes the next unused number.
public enum StarterExercise: UInt8, CaseIterable, Sendable {
  case benchPress, inclineBenchPress, dumbbellPress, dumbbellFly, chestPress, dips
  case deadlift, pullUp, latPulldown, bentOverRow, seatedRow
  case squat, legPress, legExtension, legCurl, romanianDeadlift, calfRaise
  case shoulderPress, lateralRaise, rearDeltRaise
  case bicepsCurl, hammerCurl, tricepsPushdown
  case crunch, legRaise

  public var bodyPart: BodyPart {
    switch self {
    case .benchPress, .inclineBenchPress, .dumbbellPress, .dumbbellFly, .chestPress, .dips:
      .chest
    case .deadlift, .pullUp, .latPulldown, .bentOverRow, .seatedRow: .back
    case .squat, .legPress, .legExtension, .legCurl, .romanianDeadlift, .calfRaise: .legs
    case .shoulderPress, .lateralRaise, .rearDeltRaise: .shoulders
    case .bicepsCurl, .hammerCurl, .tricepsPushdown: .arms
    case .crunch, .legRaise: .abdominals
    }
  }

  /// The identifier that every installation gives the exercise.
  public var id: ExerciseID {
    ExerciseID(
      UUID(
        uuid: (
          0x67, 0x79, 0x6D, 0x65, 0x6D, 0x6F, 0x40, 0x00, 0x80, 0x00, 0x53, 0x54, 0x41, 0x52,
          0x54, rawValue
        )))
  }
}

extension TrainingLog {
  /// The log of a new installation: the starter exercises under the given names, and no sets.
  /// A name that the log refuses leaves its exercise out.
  public static func starter(named name: (StarterExercise) -> String) -> TrainingLog {
    var log = TrainingLog.empty
    for exercise in StarterExercise.allCases {
      let command = Command.addExercise(
        id: exercise.id, name: name(exercise), bodyPart: exercise.bodyPart)
      if case .success(let transition) = log.apply(command) { log = transition.log }
    }
    return log
  }
}
