/// A sentence or label of the catalog that takes no value.
/// Each case names its key in `Localizable.xcstrings`.
public enum CopyKey: String, CaseIterable, Sendable {
  case tabLog, tabHistory, tabAnalysis, tabSettings
  case cancel, save, delete, open, replace, hideKeyboard
  case next, reviewSet, setSaved, logAnotherSet, done
  case openLog
  case edit, hide, show, discardQuestion, discardChanges, keepEditing
  case dayEmptyTitle, analysisEmptyTitle, emptyRangeTitle
  case dayNotToday, dayEmpty, addExercise, note, writeNote, editNote
  case logSet, weight, reps, kilogramUnit, weightSpoken
  case clearWeight, clearReps
  case personalBest, setEditHint, bodyweight
  case weightProblem, repsMissing, repsProblem
  case editSet, deleteSet
  case noteHint, noteCharactersProblem
  case chooseExercise, recentExercises, newExercise, editExercise
  case name, bodyPart, showWhenChoosing, deleteExercise
  case nameMissing, nameLinesProblem, nameDuplicate, exerciseHasSets, exerciseLimit
  case exerciseNotSaved, exercises, hidden
  case historyEmpty, startToday, logAnotherDay, chooseDay, dayToLog, chooseDayHint
  case weeklyTrainingDays, weeklyCaption, progressByExercise, analysisEmpty
  case estimatedOneRepMax, mostReps, personalBestEmpty, threeMonths, oneYear, allTime
  case emptyRange, oneRepMaxNote, repsNote, setsByDay, exerciseMissing
  case axisDate, axisWeekStart, axisDays
  case exportAndImport, storageHeading, storageText, shortcuts, versionLabel
  case privacyPolicy, privacyCollection, privacyCollectionText
  case privacyOnDevice, privacyOnDeviceText, privacyFiles, privacyFilesText
  case privacyDeletion, privacyDeletionText
  case watchDelivery, watchPending, watchSaved, watchRefused, watchNeedsPhone
  case watchHelp, watchWaitingHint, watchTransferFailed, retry, watch
  case watchExerciseMissing, watchIdentifierConflict, watchPhoneFull
  case exportBackupText, exportBackup, exportCSVText, exportCSV, importBackupText, importBackup
  case exported, exportFailed, imported, fileUnreadable, replaceQuestion
  case backupTooLarge, backupNotABackup, backupNewer, backupUnsupported, backupDamaged
  case csvDate, csvExercise, csvSet, csvWeight
  case saveFailed, launchFailed, launchNewer, launchLocation, launchStore
  case listSeparator, sampleNote
  case chest, back, legs, shoulders, arms, abdominals, otherBodyPart
  case starterBenchPress, starterInclineBenchPress, starterDumbbellPress, starterDumbbellFly
  case starterChestPress, starterDips, starterDeadlift, starterPullUp, starterLatPulldown
  case starterBentOverRow, starterSeatedRow, starterSquat, starterLegPress, starterLegExtension
  case starterLegCurl, starterRomanianDeadlift, starterCalfRaise, starterShoulderPress
  case starterLateralRaise, starterRearDeltRaise, starterBicepsCurl, starterHammerCurl
  case starterTricepsPushdown, starterCrunch, starterLegRaise
}

/// A sentence of the catalog that takes values, which only the typed accessors of `Copy` fill.
enum FormatKey: String, CaseIterable {
  case exerciseControlTitle
  case loadKilograms, kilogramsSpoken, setSummary, setNumber, repsCount, setsCount, daysCount
  case previousSession, noteTooLong, nameTooLong, deleteExerciseQuestion, historyRow
  case weeklyHeadline, weeklyHeadlineSingle, weekOf, lastLogged, oneRepMaxLine, mostRepsLine
  case setOnDay, heaviestWeight, overTime, version, replaceMessage
  case backupExerciseUnreadable, backupSetUnreadable, backupNoteUnreadable
  case saveFailedMessage, failureCode

  /// The keys whose English text varies with the number.
  static let plural: Set<FormatKey> = [.repsCount, .setsCount, .daysCount]
}
