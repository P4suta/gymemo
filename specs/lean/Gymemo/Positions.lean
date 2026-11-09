import Gymemo.Log

/-!
# The rules of the training log by positions

`Gymemo/Log.lean` finds and writes rows by identifier.
The Swift code keeps a dictionary from each identifier to a position, and it replaces and removes the row at that position.
The row model of the Swift tests writes the first row with an identifier.
This file states `TrainingLog.apply`, `TrainingLog.make`, and that row model line by line from the Swift code.
`Gymemo/PositionsProofs.lean` proves that both statements agree on every log that holds the invariants.
-/

namespace Gymemo.Log.Positions

/-- The position that the loop `positions[row.id] = position` leaves for a row that `found` accepts, which is the last one. -/
def lastPosition {α : Type} (found : α → Bool) : List α → Nat → Option Nat → Option Nat
  | [], _, known => known
  | row :: rest, position, known =>
    lastPosition found rest (position + 1) (if found row then some position else known)

/-- `position(of exercise:)`. -/
def exercisePosition (log : Log) (id : ExerciseID) : Option Nat :=
  lastPosition (fun row : Exercise => row.id == id) log.exercises 0 none

/-- `position(of set:)`. -/
def setPosition (log : Log) (id : SetID) : Option Nat :=
  lastPosition (fun row : LoggedSet => row.id == id) log.sets 0 none

/-- `exercise(_:)`, the row at the position of the identifier. -/
def exercise (log : Log) (id : ExerciseID) : Option Exercise :=
  (exercisePosition log id).bind (fun position => log.exercises[position]?)

/-- `set(_:)`, the row at the position of the identifier. -/
def set (log : Log) (id : SetID) : Option LoggedSet :=
  (setPosition log id).bind (fun position => log.sets[position]?)

/-- `sets(of:)`, the sets that name the exercise. -/
def setsOf (log : Log) (id : ExerciseID) : List LoggedSet :=
  log.sets.filter (fun row => row.exerciseID == id)

/-- The entries of a dictionary in the order of their days, after `dictionary[day] = nil`. -/
def without (memos : List (Day × MemoText)) (day : Day) : List (Day × MemoText) :=
  memos.filter (fun entry => !(entry.1 == day))

/-- The entries with one more entry at the place of its day. -/
def placed (entry : Day × MemoText) : List (Day × MemoText) → List (Day × MemoText)
  | [] => [entry]
  | first :: rest =>
    if entry.1 ≤ first.1 then entry :: first :: rest else first :: placed entry rest

/-- `dictionary[day] = memo` for an optional memo. -/
def assigned (memos : List (Day × MemoText)) (day : Day) : Option MemoText → List (Day × MemoText)
  | none => without memos day
  | some text => placed (day, text) (without memos day)

/-- `dictionary[day]`. -/
def lookup (memos : List (Day × MemoText)) (day : Day) : Option MemoText :=
  (memos.find? (fun entry => entry.1 == day)).map (·.2)

def addExercise (log : Log) (id : ExerciseID) (name : Name) (bodyPart : BodyPart) : Outcome :=
  if (exercise log id).isSome then .refused .duplicateIdentifier
  else if log.exercises.any (fun row => row.name == name) then .refused .duplicateExerciseName
  else if !(decide (log.exercises.length < maximumExercises)) then .refused .full
  else
    let added : Exercise := ⟨id, name, bodyPart, false⟩
    .accepted ⟨{ log with exercises := log.exercises ++ [added] }, [.putExercise added]⟩

/-- The edit writes the row at the position of the identifier, as `replaced[position] = edited` does. -/
def replaceExercise (log : Log) (id : ExerciseID) (edit : Exercise → Exercise) : Outcome :=
  match exercisePosition log id with
  | none => .refused .unknownExercise
  | some position =>
    match log.exercises[position]? with
    | none => .refused .unknownExercise
    | some current =>
      let edited := edit current
      if edited = current then unchanged log
      else if log.exercises.any (fun row => row.id != id && row.name == edited.name) then
        .refused .duplicateExerciseName
      else
        .accepted
          ⟨{ log with exercises := log.exercises.set position edited }, [.putExercise edited]⟩

/-- The removal takes the row at the position of the identifier, as `remaining.remove(at: position)` does. -/
def deleteExercise (log : Log) (id : ExerciseID) : Outcome :=
  match exercisePosition log id with
  | none => .refused .unknownExercise
  | some position =>
    if !(setsOf log id).isEmpty then .refused .exerciseHasSets
    else
      .accepted ⟨{ log with exercises := log.exercises.eraseIdx position }, [.removeExercise id]⟩

def logSet (log : Log) (row : LoggedSet) : Outcome :=
  if (exercise log row.exerciseID).isNone then .refused .unknownExercise
  else if (set log row.id).isSome then .refused .duplicateIdentifier
  else if !(decide (log.sets.length < maximumSets)) then .refused .full
  else .accepted ⟨{ log with sets := log.sets ++ [row] }, [.putSet row]⟩

def editSet (log : Log) (id : SetID) (weight reps : Nat) : Outcome :=
  match setPosition log id with
  | none => .refused .unknownSet
  | some position =>
    match log.sets[position]? with
    | none => .refused .unknownSet
    | some current =>
      let edited : LoggedSet := { current with weight := weight, reps := reps }
      if edited = current then unchanged log
      else .accepted ⟨{ log with sets := log.sets.set position edited }, [.putSet edited]⟩

def deleteSet (log : Log) (id : SetID) : Outcome :=
  match setPosition log id with
  | none => .refused .unknownSet
  | some position =>
    .accepted ⟨{ log with sets := log.sets.eraseIdx position }, [.removeSet id]⟩

def writeMemo (log : Log) (day : Day) (memo : Option MemoText) : Outcome :=
  if memo = lookup log.memos day then unchanged log
  else
    let change : Change :=
      match memo with
      | some text => .putMemo day text
      | none => .removeMemo day
    .accepted ⟨{ log with memos := assigned log.memos day memo }, [change]⟩

/-- `TrainingLog.apply`, by positions. -/
def apply (log : Log) : Command → Outcome
  | .addExercise _ (.refused refusal) _ => .refused (.exerciseName refusal)
  | .addExercise id (.accepted name) bodyPart => addExercise log id name bodyPart
  | .editExercise _ (.refused refusal) _ => .refused (.exerciseName refusal)
  | .editExercise id (.accepted name) bodyPart =>
    replaceExercise log id (fun row => { row with name := name, bodyPart := bodyPart })
  | .setExerciseArchived id isArchived =>
    replaceExercise log id (fun row => { row with isArchived := isArchived })
  | .deleteExercise id => deleteExercise log id
  | .logSet id exerciseID day weight reps => logSet log ⟨id, exerciseID, day, weight, reps⟩
  | .editSet id weight reps => editSet log id weight reps
  | .deleteSet id => deleteSet log id
  | .writeMemo _ (.refused refusal) => .refused (.memo refusal)
  | .writeMemo day .nothing => writeMemo log day none
  | .writeMemo day (.kept text) => writeMemo log day (some text)
  | .replaceAll replacement => .accepted ⟨replacement, [.replaceAll replacement]⟩

/-- The row model of the Swift tests for one change: a put writes the first row with the identifier, or appends. -/
def storeRow (rows : Log) : Change → Log
  | .putExercise exercise =>
    match rows.exercises.findIdx? (fun row => row.id == exercise.id) with
    | some index => { rows with exercises := rows.exercises.set index exercise }
    | none => { rows with exercises := rows.exercises ++ [exercise] }
  | .removeExercise id =>
    { rows with exercises := rows.exercises.filter (fun row => !(row.id == id)) }
  | .putSet set =>
    match rows.sets.findIdx? (fun row => row.id == set.id) with
    | some index => { rows with sets := rows.sets.set index set }
    | none => { rows with sets := rows.sets ++ [set] }
  | .removeSet id => { rows with sets := rows.sets.filter (fun row => !(row.id == id)) }
  | .putMemo day text => { rows with memos := assigned rows.memos day (some text) }
  | .removeMemo day => { rows with memos := assigned rows.memos day none }
  | .replaceAll log => log

def storeRows (rows : Log) (changes : List Change) : Log :=
  changes.foldl storeRow rows

/-- The loop over the exercises of `TrainingLog.make`, which keeps the identifier before it reads the name. -/
def readExercises :
    List Exercise → List ExerciseID → List Name → Except IntegrityRefusal (List ExerciseID)
  | [], ids, _ => .ok ids
  | row :: rest, ids, names =>
    if ids.contains row.id then .error .duplicateExerciseID
    else if names.contains row.name then .error .duplicateExerciseName
    else readExercises rest (row.id :: ids) (row.name :: names)

/-- The loop over the sets of `TrainingLog.make`. -/
def readSets (exerciseIDs : List ExerciseID) : List LoggedSet → List SetID → Option IntegrityRefusal
  | [], _ => none
  | row :: rest, ids =>
    if ids.contains row.id then some .duplicateSetID
    else if !(exerciseIDs.contains row.exerciseID) then some .unknownExercise
    else readSets exerciseIDs rest (row.id :: ids)

/-- `TrainingLog.make`, with the identifiers that its first loop collected. -/
def make (rows : Log) : Option IntegrityRefusal :=
  if !(decide (rows.exercises.length ≤ maximumExercises)) then some .tooManyExercises
  else if !(decide (rows.sets.length ≤ maximumSets)) then some .tooManySets
  else
    match readExercises rows.exercises [] [] with
    | .error refusal => some refusal
    | .ok exerciseIDs => readSets exerciseIDs rows.sets []

/-- The step of each command in turn, with the log after the last one.
A refused command leaves the log alone. -/
def outcomes (log : Log) : List Command → List Step × Log
  | [] => ([], log)
  | command :: rest =>
    match apply log command with
    | .refused refusal =>
      let (later, final) := outcomes log rest
      (.refused refusal :: later, final)
    | .accepted transition =>
      let (later, final) := outcomes transition.log rest
      (.changed transition.changes :: later, final)

end Gymemo.Log.Positions
