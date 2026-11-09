/-!
# The rules of the training log

`Sources/GymemoCore/Command.swift` applies one command to a log and returns the new log with the row changes that make a store match it.
`Sources/GymemoCore/TrainingLog.swift` states the log's invariants and checks rows of unknown origin.
This file states the same rules over lists.
The Swift code names rows by UUID and holds text, and this model names rows, names, and memo texts by natural numbers.
A command carries what `ExerciseName.parse` and `Memo.parse` made of its text, so the model starts where parsing ends.
`Gymemo/LogVectors.lean` holds results of the Swift code, and Lean checks that this model gives the same ones.
-/

namespace Gymemo.Log

abbrev ExerciseID := Nat
abbrev SetID := Nat
abbrev Name := Nat
abbrev MemoText := Nat
/-- The number of days since 1970-01-01, as `LocalDay.dayNumber`. -/
abbrev Day := Int

inductive BodyPart
  | chest | back | legs | shoulders | arms | abdominals | other
deriving DecidableEq, Repr

structure Exercise where
  id : ExerciseID
  name : Name
  bodyPart : BodyPart
  isArchived : Bool
deriving DecidableEq, Repr

structure LoggedSet where
  id : SetID
  exerciseID : ExerciseID
  day : Day
  /-- Hundredths of a kilogram. -/
  weight : Nat
  reps : Nat
deriving DecidableEq, Repr

/-- Every exercise, set, and memo of one lifter, with the memos in the order of their days. -/
structure Log where
  exercises : List Exercise
  sets : List LoggedSet
  memos : List (Day × MemoText)
deriving DecidableEq, Repr

def Log.empty : Log := ⟨[], [], []⟩

def maximumExercises : Nat := 1000
def maximumSets : Nat := 1000000

inductive NameRefusal
  | empty | tooLong | controlCharacter
deriving DecidableEq, Repr

inductive MemoRefusal
  | tooLong | controlCharacter
deriving DecidableEq, Repr

inductive Refusal
  | exerciseName (refusal : NameRefusal)
  | duplicateExerciseName
  | duplicateIdentifier
  | unknownExercise
  | exerciseHasSets
  | unknownSet
  | memo (refusal : MemoRefusal)
  | full
deriving DecidableEq, Repr

/-- What `ExerciseName.parse` made of a command's text. -/
inductive NameInput
  | refused (refusal : NameRefusal)
  | accepted (name : Name)
deriving DecidableEq, Repr

/-- What `Memo.parse` made of a command's text, where `nothing` is a text that holds nothing to keep. -/
inductive MemoInput
  | refused (refusal : MemoRefusal)
  | nothing
  | kept (text : MemoText)
deriving DecidableEq, Repr

inductive Command
  | addExercise (id : ExerciseID) (name : NameInput) (bodyPart : BodyPart)
  | editExercise (id : ExerciseID) (name : NameInput) (bodyPart : BodyPart)
  | setExerciseArchived (id : ExerciseID) (isArchived : Bool)
  | deleteExercise (id : ExerciseID)
  | logSet (id : SetID) (exerciseID : ExerciseID) (day : Day) (weight : Nat) (reps : Nat)
  | editSet (id : SetID) (weight : Nat) (reps : Nat)
  | deleteSet (id : SetID)
  | writeMemo (day : Day) (memo : MemoInput)
  | replaceAll (log : Log)
deriving DecidableEq, Repr

/-- One stored row to write or remove. -/
inductive Change
  | putExercise (exercise : Exercise)
  | removeExercise (id : ExerciseID)
  | putSet (set : LoggedSet)
  | removeSet (id : SetID)
  | putMemo (day : Day) (text : MemoText)
  | removeMemo (day : Day)
  | replaceAll (log : Log)
deriving DecidableEq, Repr

/-- The log after a command, with the row changes that make a store match it. -/
structure Transition where
  log : Log
  changes : List Change
deriving DecidableEq, Repr

/-- What a command gives: a refusal that leaves the log alone, or a transition. -/
inductive Outcome
  | refused (refusal : Refusal)
  | accepted (transition : Transition)
deriving DecidableEq, Repr

def Log.exercise? (log : Log) (id : ExerciseID) : Option Exercise :=
  log.exercises.find? (fun exercise => exercise.id == id)

def Log.set? (log : Log) (id : SetID) : Option LoggedSet :=
  log.sets.find? (fun set => set.id == id)

def Log.memo? (log : Log) (day : Day) : Option MemoText :=
  (log.memos.find? (fun entry => entry.1 == day)).map (·.2)

/-- The memos with `text` on `day`, kept in the order of their days. -/
def insertMemo : List (Day × MemoText) → Day → MemoText → List (Day × MemoText)
  | [], day, text => [(day, text)]
  | (first, kept) :: rest, day, text =>
    if day < first then (day, text) :: (first, kept) :: rest
    else if day = first then (day, text) :: rest
    else (first, kept) :: insertMemo rest day text

def writeMemos (memos : List (Day × MemoText)) (day : Day) : Option MemoText → List (Day × MemoText)
  | none => memos.filter (fun entry => entry.1 != day)
  | some text => insertMemo memos day text

def unchanged (log : Log) : Outcome := .accepted ⟨log, []⟩

def addExercise (log : Log) (id : ExerciseID) (name : Name) (bodyPart : BodyPart) : Outcome :=
  if (log.exercise? id).isSome then .refused .duplicateIdentifier
  else if log.exercises.any (fun exercise => exercise.name == name) then
    .refused .duplicateExerciseName
  else if log.exercises.length < maximumExercises then
    let added : Exercise := ⟨id, name, bodyPart, false⟩
    .accepted ⟨{ log with exercises := log.exercises ++ [added] }, [.putExercise added]⟩
  else .refused .full

def replaceExercise (log : Log) (id : ExerciseID) (edit : Exercise → Exercise) : Outcome :=
  match log.exercise? id with
  | none => .refused .unknownExercise
  | some current =>
    let edited := edit current
    if edited = current then unchanged log
    else if log.exercises.any (fun other => other.id != id && other.name == edited.name) then
      .refused .duplicateExerciseName
    else
      let replaced := log.exercises.map (fun exercise => if exercise.id = id then edited else exercise)
      .accepted ⟨{ log with exercises := replaced }, [.putExercise edited]⟩

def deleteExercise (log : Log) (id : ExerciseID) : Outcome :=
  if (log.exercise? id).isNone then .refused .unknownExercise
  else if log.sets.any (fun set => set.exerciseID == id) then .refused .exerciseHasSets
  else
    let remaining := log.exercises.filter (fun exercise => exercise.id != id)
    .accepted ⟨{ log with exercises := remaining }, [.removeExercise id]⟩

def logSet (log : Log) (set : LoggedSet) : Outcome :=
  if (log.exercise? set.exerciseID).isNone then .refused .unknownExercise
  else if (log.set? set.id).isSome then .refused .duplicateIdentifier
  else if log.sets.length < maximumSets then
    .accepted ⟨{ log with sets := log.sets ++ [set] }, [.putSet set]⟩
  else .refused .full

def editSet (log : Log) (id : SetID) (weight reps : Nat) : Outcome :=
  match log.set? id with
  | none => .refused .unknownSet
  | some current =>
    let edited : LoggedSet := { current with weight := weight, reps := reps }
    if edited = current then unchanged log
    else
      let replaced := log.sets.map (fun set => if set.id = id then edited else set)
      .accepted ⟨{ log with sets := replaced }, [.putSet edited]⟩

def deleteSet (log : Log) (id : SetID) : Outcome :=
  if (log.set? id).isNone then .refused .unknownSet
  else
    let remaining := log.sets.filter (fun set => set.id != id)
    .accepted ⟨{ log with sets := remaining }, [.removeSet id]⟩

def writeMemo (log : Log) (day : Day) (memo : Option MemoText) : Outcome :=
  if memo = log.memo? day then unchanged log
  else
    let change : Change :=
      match memo with
      | some text => .putMemo day text
      | none => .removeMemo day
    .accepted ⟨{ log with memos := writeMemos log.memos day memo }, [change]⟩

/-- `TrainingLog.apply`. -/
def apply (log : Log) : Command → Outcome
  | .addExercise _ (.refused refusal) _ => .refused (.exerciseName refusal)
  | .addExercise id (.accepted name) bodyPart => addExercise log id name bodyPart
  | .editExercise _ (.refused refusal) _ => .refused (.exerciseName refusal)
  | .editExercise id (.accepted name) bodyPart =>
    replaceExercise log id (fun exercise => { exercise with name := name, bodyPart := bodyPart })
  | .setExerciseArchived id isArchived =>
    replaceExercise log id (fun exercise => { exercise with isArchived := isArchived })
  | .deleteExercise id => deleteExercise log id
  | .logSet id exerciseID day weight reps => logSet log ⟨id, exerciseID, day, weight, reps⟩
  | .editSet id weight reps => editSet log id weight reps
  | .deleteSet id => deleteSet log id
  | .writeMemo _ (.refused refusal) => .refused (.memo refusal)
  | .writeMemo day .nothing => writeMemo log day none
  | .writeMemo day (.kept text) => writeMemo log day (some text)
  | .replaceAll replacement => .accepted ⟨replacement, [.replaceAll replacement]⟩

/-- A put replaces the row with the same identifier or appends a new row after the existing ones. -/
def putExercise (rows : List Exercise) (exercise : Exercise) : List Exercise :=
  if rows.any (fun row => row.id == exercise.id) then
    rows.map (fun row => if row.id = exercise.id then exercise else row)
  else rows ++ [exercise]

def putSet (rows : List LoggedSet) (set : LoggedSet) : List LoggedSet :=
  if rows.any (fun row => row.id == set.id) then
    rows.map (fun row => if row.id = set.id then set else row)
  else rows ++ [set]

/-- The rows of a store after one change. -/
def store (rows : Log) : Change → Log
  | .putExercise exercise => { rows with exercises := putExercise rows.exercises exercise }
  | .removeExercise id =>
    { rows with exercises := rows.exercises.filter (fun row => row.id != id) }
  | .putSet set => { rows with sets := putSet rows.sets set }
  | .removeSet id => { rows with sets := rows.sets.filter (fun row => row.id != id) }
  | .putMemo day text => { rows with memos := insertMemo rows.memos day text }
  | .removeMemo day => { rows with memos := rows.memos.filter (fun entry => entry.1 != day) }
  | .replaceAll log => log

def storeAll (rows : Log) (changes : List Change) : Log :=
  changes.foldl store rows

/-- The invariants of a log.
Exercise identifiers, exercise names, and set identifiers are unique, every set names a stored exercise, and the counts stay within the limits.
The memos lie in the order of their days, which stands for the dictionary of the Swift code. -/
structure Valid (log : Log) : Prop where
  exerciseIDs : (log.exercises.map (·.id)).Nodup
  exerciseNames : (log.exercises.map (·.name)).Nodup
  setIDs : (log.sets.map (·.id)).Nodup
  setsNameExercises : ∀ set ∈ log.sets, ∃ exercise ∈ log.exercises, exercise.id = set.exerciseID
  exerciseCount : log.exercises.length ≤ maximumExercises
  setCount : log.sets.length ≤ maximumSets
  memoDays : (log.memos.map (·.1)).Pairwise (· < ·)

/-- A command that the Swift code can build: a replacement is a `TrainingLog`, which holds the invariants. -/
def Admissible : Command → Prop
  | .replaceAll log => Valid log
  | _ => True

inductive IntegrityRefusal
  | duplicateExerciseID
  | duplicateExerciseName
  | duplicateSetID
  | unknownExercise
  | tooManyExercises
  | tooManySets
deriving DecidableEq, Repr

/-- The first exercise that repeats an identifier or a name, read as `TrainingLog.make` reads the rows. -/
def checkExercises : List Exercise → List ExerciseID → List Name → Option IntegrityRefusal
  | [], _, _ => none
  | exercise :: rest, ids, names =>
    if ids.contains exercise.id then some .duplicateExerciseID
    else if names.contains exercise.name then some .duplicateExerciseName
    else checkExercises rest (exercise.id :: ids) (exercise.name :: names)

/-- The first set that repeats an identifier or names no stored exercise. -/
def checkSets (exercises : List Exercise) : List LoggedSet → List SetID → Option IntegrityRefusal
  | [], _ => none
  | set :: rest, ids =>
    if ids.contains set.id then some .duplicateSetID
    else if exercises.any (fun exercise => exercise.id == set.exerciseID) then
      checkSets exercises rest (set.id :: ids)
    else some .unknownExercise

/-- `TrainingLog.make`: the first broken invariant of the rows, or nothing when they form a log. -/
def make (rows : Log) : Option IntegrityRefusal :=
  if maximumExercises < rows.exercises.length then some .tooManyExercises
  else if maximumSets < rows.sets.length then some .tooManySets
  else
    match checkExercises rows.exercises [] [] with
    | some refusal => some refusal
    | none => checkSets rows.exercises rows.sets []

/-- What one command of a sequence gave: its refusal, or the changes it returned. -/
inductive Step
  | refused (refusal : Refusal)
  | changed (changes : List Change)
deriving DecidableEq, Repr

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

/-- The rows of a store that receives the changes of each accepted command in turn. -/
def stored (log rows : Log) : List Command → Log
  | [] => rows
  | command :: rest =>
    match apply log command with
    | .refused _ => stored log rows rest
    | .accepted transition => stored transition.log (storeAll rows transition.changes) rest

/-- The log after each accepted command in turn. -/
def applied (log : Log) : List Command → Log
  | [] => log
  | command :: rest =>
    match apply log command with
    | .refused _ => applied log rest
    | .accepted transition => applied transition.log rest

end Gymemo.Log
