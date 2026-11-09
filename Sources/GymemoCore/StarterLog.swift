import Foundation

extension TrainingLog {
  /// The log of a new installation: common exercises and no sets.
  public static let starter = makeStarter()

  private static let starterExercises: [(name: String, bodyPart: BodyPart)] = [
    ("ベンチプレス", .chest), ("インクラインベンチプレス", .chest), ("ダンベルプレス", .chest),
    ("ダンベルフライ", .chest), ("チェストプレス", .chest), ("ディップス", .chest),
    ("デッドリフト", .back), ("懸垂", .back), ("ラットプルダウン", .back),
    ("ベントオーバーロー", .back), ("シーテッドロー", .back),
    ("スクワット", .legs), ("レッグプレス", .legs), ("レッグエクステンション", .legs),
    ("レッグカール", .legs), ("ルーマニアンデッドリフト", .legs), ("カーフレイズ", .legs),
    ("ショルダープレス", .shoulders), ("サイドレイズ", .shoulders), ("リアレイズ", .shoulders),
    ("アームカール", .arms), ("ハンマーカール", .arms), ("トライセプスプレスダウン", .arms),
    ("クランチ", .abdominals), ("レッグレイズ", .abdominals),
  ]

  /// Starter exercises carry fixed identifiers, so every installation builds the same log.
  private static func makeStarter() -> TrainingLog {
    var log = TrainingLog.empty
    for (index, entry) in starterExercises.enumerated() {
      let id = ExerciseID(
        UUID(
          uuid: (
            0x67, 0x79, 0x6D, 0x65, 0x6D, 0x6F, 0x40, 0x00, 0x80, 0x00, 0x53, 0x54, 0x41, 0x52,
            0x54, UInt8(truncatingIfNeeded: index)
          )))
      let command = Command.addExercise(id: id, name: entry.name, bodyPart: entry.bodyPart)
      if case .success(let transition) = log.apply(command) { log = transition.log }
    }
    return log
  }
}
