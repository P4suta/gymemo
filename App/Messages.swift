import GymemoCore

/// The Japanese sentence for each refusal, which says how to fix the input.
enum Messages {
  static func entry(_ refusal: SetEntryRefusal) -> String {
    switch refusal {
    case .weight:
      "重量は0から999.99までの数字で入力してください。自重のセットは空欄にします。"
    case .reps(.empty):
      "回数を入力してください。"
    case .reps:
      "回数は1から999までの整数で入力してください。"
    }
  }

  static func exercise(_ refusal: Refusal) -> String {
    switch refusal {
    case .exerciseName(.empty): "名前を入力してください。"
    case .exerciseName(.tooLong): "名前は\(ExerciseName.maximumLength)文字以内で入力してください。"
    case .exerciseName(.controlCharacter): "名前は1行で入力してください。"
    case .duplicateExerciseName: "同じ名前の種目がすでにあります。別の名前を入力してください。"
    case .exerciseHasSets: "セットを記録した種目は削除できません。選択一覧から隠せます。"
    case .full: "種目の数が上限に達しました。使わない種目を削除してください。"
    case .duplicateIdentifier, .unknownExercise, .unknownSet, .memo:
      "種目を保存できませんでした。画面を開き直して、もう一度試してください。"
    }
  }

  static func memo(_ refusal: Refusal) -> String {
    switch refusal {
    case .memo(.tooLong): "メモは\(Memo.maximumLength)文字以内で入力してください。"
    default: "メモに使えない文字が入っています。貼り付けた文字を消して、入力し直してください。"
    }
  }

  static func backup(_ refusal: BackupRefusal) -> String {
    switch refusal {
    case .tooLarge:
      "ファイルが大きすぎます。gymemoが書き出したバックアップを選んでください。"
    case .notABackup:
      "gymemoのバックアップではありません。gymemoが書き出したJSONファイルを選んでください。"
    case .unsupportedVersion(let version) where version > Backup.formatVersion:
      "新しいバージョンのアプリで作られたバックアップです。アプリを更新してから読み込んでください。"
    case .unsupportedVersion:
      "読み込めない形式のバックアップです。gymemoが書き出したJSONファイルを選んでください。"
    case .invalidExercise(let index):
      "バックアップの種目の\(index + 1)件目を読めません。ファイルが壊れている可能性があります。"
    case .invalidSet(let index):
      "バックアップのセットの\(index + 1)件目を読めません。ファイルが壊れている可能性があります。"
    case .invalidMemo(let index):
      "バックアップのメモの\(index + 1)件目を読めません。ファイルが壊れている可能性があります。"
    case .integrity:
      "バックアップの内容がそろっていません。ファイルが壊れている可能性があります。"
    }
  }
}
