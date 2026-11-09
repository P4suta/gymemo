import Gymemo.Log

/-!
# The store after the changes of a command

`TrainingLog.apply` returns the new log with the row changes that make a store match it, and `Sources/GymemoKit/TrainingLogStore.swift` writes those changes to a SQLite database.
This file proves the contract between the two over the model of `Gymemo/Log.lean`.
A store that holds the rows of a log and applies the returned changes holds the rows of the new log.
The log and the store of the model replace and remove rows by identifier alike, so the proofs read no invariant of the log.
-/

namespace Gymemo.Log

/-- A list holds a row that passes a test exactly when the search for the first such row finds one. -/
private theorem any_eq_isSome_find? {Row : Type} (test : Row → Bool) (rows : List Row) :
    rows.any test = (rows.find? test).isSome := by
  induction rows with
  | nil => rfl
  | cons first rest hypothesis =>
    rw [List.any_cons, List.find?_cons]
    cases test first with
    | true => rfl
    | false => exact hypothesis

/-- The row that a search finds passes the test. -/
private theorem found_passes {Row : Type} {test : Row → Bool} {rows : List Row} {row : Row}
    (search : rows.find? test = some row) : test row = true := by
  induction rows with
  | nil => cases search
  | cons first rest hypothesis =>
    rw [List.find?_cons] at search
    cases passes : test first with
    | true =>
      rw [passes] at search
      cases search
      exact passes
    | false =>
      rw [passes] at search
      exact hypothesis search

/-- A put of an exercise whose identifier no row has appends the exercise. -/
private theorem putExercise_absent {rows : List Exercise} {exercise : Exercise}
    (absent : ¬(rows.find? (fun row => row.id == exercise.id)).isSome = true) :
    putExercise rows exercise = rows ++ [exercise] := by
  unfold putExercise
  rw [any_eq_isSome_find?, ite_eq_right absent]

/-- A put of an exercise with the identifier of the row found under `id` replaces every row under `id`. -/
private theorem putExercise_present {rows : List Exercise} {exercise current : Exercise}
    {id : ExerciseID} (found : rows.find? (fun row => row.id == id) = some current)
    (sameID : exercise.id = current.id) :
    putExercise rows exercise = rows.map (fun row => if row.id = id then exercise else row) := by
  have passes : (current.id == id) = true := found_passes (row := current) found
  have named : exercise.id = id := sameID.trans (of_decide_eq_true passes)
  subst named
  unfold putExercise
  rw [any_eq_isSome_find?, found]
  rfl

/-- A put of a set whose identifier no row has appends the set. -/
private theorem putSet_absent {rows : List LoggedSet} {set : LoggedSet}
    (absent : ¬(rows.find? (fun row => row.id == set.id)).isSome = true) :
    putSet rows set = rows ++ [set] := by
  unfold putSet
  rw [any_eq_isSome_find?, ite_eq_right absent]

/-- A put of a set with the identifier of the row found under `id` replaces every row under `id`. -/
private theorem putSet_present {rows : List LoggedSet} {set current : LoggedSet} {id : SetID}
    (found : rows.find? (fun row => row.id == id) = some current) (sameID : set.id = current.id) :
    putSet rows set = rows.map (fun row => if row.id = id then set else row) := by
  have passes : (current.id == id) = true := found_passes (row := current) found
  have named : set.id = id := sameID.trans (of_decide_eq_true passes)
  subst named
  unfold putSet
  rw [any_eq_isSome_find?, found]
  rfl

/-- A store that holds the rows of `log` and applies the changes of an accepted `outcome` holds the rows of its log. -/
private def Rebuilds (log : Log) (outcome : Outcome) : Prop :=
  ∀ transition, outcome = .accepted transition → storeAll log transition.changes = transition.log

/-- A refusal carries no transition, so the rule asks nothing of it. -/
private theorem refused_rebuilds {log : Log} {refusal : Refusal} :
    Rebuilds log (.refused refusal) :=
  fun _ accepted => nomatch accepted

/-- A transition rebuilds when a store that applies its changes holds its log. -/
private theorem accepted_rebuilds {log after : Log} {changes : List Change}
    (rebuilt : storeAll log changes = after) : Rebuilds log (.accepted ⟨after, changes⟩) :=
  fun | _, rfl => rebuilt

/-- A command that changes nothing returns the log without a change. -/
private theorem unchanged_rebuilds {log : Log} : Rebuilds log (unchanged log) :=
  accepted_rebuilds rfl

/-- An `if` rebuilds when its first branch rebuilds and its second branch rebuilds where the condition fails. -/
private theorem ite_rebuilds {log : Log} {condition : Prop} [Decidable condition]
    {first second : Outcome} (whenTrue : Rebuilds log first)
    (whenFalse : ¬condition → Rebuilds log second) :
    Rebuilds log (if condition then first else second) := by
  by_cases holds : condition
  · rw [ite_eq_left holds]
    exact whenTrue
  · rw [ite_eq_right holds]
    exact whenFalse holds

/-- A transition with one put of an exercise rebuilds when its log holds the exercises that the put gives. -/
private theorem putExercise_rebuilds {log : Log} {exercise : Exercise} {exercises : List Exercise}
    (put : putExercise log.exercises exercise = exercises) :
    Rebuilds log (.accepted ⟨{ log with exercises := exercises }, [.putExercise exercise]⟩) :=
  accepted_rebuilds (congrArg (fun rows => { log with exercises := rows }) put)

/-- A transition with one put of a set rebuilds when its log holds the sets that the put gives. -/
private theorem putSet_rebuilds {log : Log} {set : LoggedSet} {sets : List LoggedSet}
    (put : putSet log.sets set = sets) :
    Rebuilds log (.accepted ⟨{ log with sets := sets }, [.putSet set]⟩) :=
  accepted_rebuilds (congrArg (fun rows => { log with sets := rows }) put)

/-- `addExercise` accepts an exercise whose identifier no exercise has, so the put appends it as the log does. -/
private theorem addExercise_rebuilds (log : Log) (id : ExerciseID) (name : Name)
    (bodyPart : BodyPart) : Rebuilds log (addExercise log id name bodyPart) :=
  ite_rebuilds refused_rebuilds fun unknown =>
  ite_rebuilds refused_rebuilds fun _ =>
  ite_rebuilds (putExercise_rebuilds (putExercise_absent unknown)) fun _ =>
  refused_rebuilds

/-- `replaceExercise` edits the exercise found under `id`, so an edit that keeps the identifier puts it over every row under `id` as the log does. -/
private theorem replaceExercise_rebuilds {log : Log} {id : ExerciseID} {edit : Exercise → Exercise}
    (keepsID : ∀ exercise, (edit exercise).id = exercise.id) :
    Rebuilds log (replaceExercise log id edit) := by
  unfold replaceExercise
  cases found : log.exercise? id with
  | none => exact refused_rebuilds
  | some current =>
    exact
      ite_rebuilds unchanged_rebuilds fun _ =>
      ite_rebuilds refused_rebuilds fun _ =>
      putExercise_rebuilds (putExercise_present found (keepsID current))

/-- `deleteExercise` and the store remove the rows under `id` by the same filter. -/
private theorem deleteExercise_rebuilds (log : Log) (id : ExerciseID) :
    Rebuilds log (deleteExercise log id) :=
  ite_rebuilds refused_rebuilds fun _ =>
  ite_rebuilds refused_rebuilds fun _ =>
  accepted_rebuilds rfl

/-- `logSet` accepts a set whose identifier no set has, so the put appends it as the log does. -/
private theorem logSet_rebuilds (log : Log) (set : LoggedSet) : Rebuilds log (logSet log set) :=
  ite_rebuilds refused_rebuilds fun _ =>
  ite_rebuilds refused_rebuilds fun unknown =>
  ite_rebuilds (putSet_rebuilds (putSet_absent unknown)) fun _ =>
  refused_rebuilds

/-- `editSet` edits the set found under `id` and keeps its identifier, so the put replaces every row under `id` as the log does. -/
private theorem editSet_rebuilds (log : Log) (id : SetID) (weight reps : Nat) :
    Rebuilds log (editSet log id weight reps) := by
  unfold editSet
  cases found : log.set? id with
  | none => exact refused_rebuilds
  | some current =>
    exact
      ite_rebuilds unchanged_rebuilds fun _ =>
      putSet_rebuilds (putSet_present found rfl)

/-- `deleteSet` and the store remove the rows under `id` by the same filter. -/
private theorem deleteSet_rebuilds (log : Log) (id : SetID) : Rebuilds log (deleteSet log id) :=
  ite_rebuilds refused_rebuilds fun _ =>
  accepted_rebuilds rfl

/-- `writeMemo` and the store write or remove the memo of a day by the same functions. -/
private theorem writeMemo_rebuilds (log : Log) (day : Day) (memo : Option MemoText) :
    Rebuilds log (writeMemo log day memo) :=
  ite_rebuilds unchanged_rebuilds fun _ =>
  match memo with
  | none => accepted_rebuilds rfl
  | some _ => accepted_rebuilds rfl

/-- Every command rebuilds from every log, and the log need not be valid.
Each line proves the line of `apply` with the same pattern. -/
private theorem command_rebuilds (log : Log) :
    (command : Command) → Rebuilds log (apply log command)
  | .addExercise _ (.refused _) _ => refused_rebuilds
  | .addExercise id (.accepted name) bodyPart => addExercise_rebuilds log id name bodyPart
  | .editExercise _ (.refused _) _ => refused_rebuilds
  | .editExercise _ (.accepted _) _ => replaceExercise_rebuilds fun _ => rfl
  | .setExerciseArchived _ _ => replaceExercise_rebuilds fun _ => rfl
  | .deleteExercise id => deleteExercise_rebuilds log id
  | .logSet id exerciseID day weight reps => logSet_rebuilds log ⟨id, exerciseID, day, weight, reps⟩
  | .editSet id weight reps => editSet_rebuilds log id weight reps
  | .deleteSet id => deleteSet_rebuilds log id
  | .writeMemo _ (.refused _) => refused_rebuilds
  | .writeMemo day .nothing => writeMemo_rebuilds log day none
  | .writeMemo day (.kept text) => writeMemo_rebuilds log day (some text)
  | .replaceAll _ => accepted_rebuilds rfl

/-- A store that holds the rows of a log and applies the changes of an accepted command holds the rows of the new log.
This is the contract between `TrainingLog.apply` and the SQLite adapter.
`command_rebuilds` proves it for every log, so this proof reads no invariant and names `valid` only for the unused-variable linter. -/
theorem apply_rebuilds {log : Log} {command : Command} {transition : Transition}
    (valid : Valid log) (accepted : apply log command = .accepted transition) :
    storeAll log transition.changes = transition.log :=
  have _ := valid
  command_rebuilds log command transition accepted

/-- Over any sequence of commands, a store that receives the changes of each accepted command holds the rows of the log.
The hypothesis `preserved` says that an accepted command keeps the invariants, and it carries `valid` from each log to the next for `apply_rebuilds`. -/
theorem stored_eq_applied {log : Log} {commands : List Command} (valid : Valid log)
    (admissible : ∀ command ∈ commands, Admissible command)
    (preserved : ∀ {before : Log} {command : Command} {transition : Transition},
      Valid before → Admissible command → apply before command = .accepted transition →
        Valid transition.log) :
    stored log log commands = applied log commands := by
  induction commands generalizing log with
  | nil => rfl
  | cons command rest hypothesis =>
    have later : ∀ following ∈ rest, Admissible following :=
      fun following member => admissible following (List.mem_cons_of_mem command member)
    rw [stored, applied]
    cases outcome : apply log command with
    | refused _ => exact hypothesis valid later
    | accepted transition =>
      have rebuilt : storeAll log transition.changes = transition.log :=
        apply_rebuilds valid outcome
      have kept : Valid transition.log :=
        preserved valid (admissible command List.mem_cons_self) outcome
      show stored transition.log (storeAll log transition.changes) rest = _
      rw [rebuilt]
      exact hypothesis kept later

end Gymemo.Log
