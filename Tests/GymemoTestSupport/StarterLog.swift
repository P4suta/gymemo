import GymemoCore

extension TrainingLog {
  /// The starter log with each exercise named after its case, such as `benchPress`.
  public static let starter = TrainingLog.starter { "\($0)" }
}
