import Gymemo.Log

/-!
# The order of the rows after a command

`Sources/GymemoCore/TrainingLog.swift` keeps the exercises and the sets in the order in which the lifter added them.
A predicate of one log cannot say that, so this file states it over one accepted command of the model in `Gymemo/Log.lean`.
After an accepted command other than a replacement, the identifiers of the rows stand as before, or as before with one new identifier at the end, or as before with one identifier erased.
A row that survives the command is unchanged unless the command returns the put of exactly that row.
The proofs read the invariant that identifiers are unique, because a filter by identifier erases one identifier only when no other row shares it.
-/

namespace Gymemo.Log

/-- How a command leaves a list of rows with a key.
The rows stay as they were, gain one row under a new key at the end, have every row under a key replaced by one row with that key, or lose the rows under a key.
A row that the command appends or replaces is the row of the one put that the command returns. -/
private inductive RowsAfter {Row : Type} (key : Row → Nat) (put : Row → Change)
    (before : List Row) (changes : List Change) : List Row → Prop
  | kept : RowsAfter key put before changes before
  | appended (row : Row) (fresh : key row ∉ before.map key) (named : changes = [put row]) :
    RowsAfter key put before changes (before ++ [row])
  | replaced (id : Nat) (row : Row) (keyed : key row = id) (named : changes = [put row]) :
    RowsAfter key put before changes
      (before.map (fun other => if key other = id then row else other))
  | removed (id : Nat) :
    RowsAfter key put before changes (before.filter (fun other => key other != id))

/-- The test `a != b` passes for two different numbers.
The proof reads the test as the decision of `a = b`, as the instance that the model's rows use defines it. -/
private theorem bne_of_ne {a b : Nat} (apart : a ≠ b) : (a != b) = true :=
  congrArg (!·) (decide_eq_false apart)

/-- The test `a != b` fails for two equal numbers. -/
private theorem not_bne_of_eq {a b : Nat} (same : a = b) : ¬(a != b) = true :=
  fun passes => nomatch (congrArg (!·) (decide_eq_true same)).symm.trans passes

/-- The key of a row of a list lies among the keys of the list. -/
private theorem key_mem {Row : Type} {key : Row → Nat} {rows : List Row} {row : Row}
    (member : row ∈ rows) : key row ∈ rows.map key := by
  induction rows with
  | nil => exact absurd member List.not_mem_nil
  | cons head rest hypothesis =>
    rw [List.map_cons]
    cases List.mem_cons.mp member with
    | inl atHead => exact List.mem_cons.mpr (Or.inl (congrArg key atHead))
    | inr inRest => exact List.mem_cons_of_mem _ (hypothesis inRest)

/-- A value among the images of the rows of a list is the image of one of them. -/
private theorem image_of_mem {Row Value : Type} {image : Row → Value} {rows : List Row}
    {value : Value} (member : value ∈ rows.map image) : ∃ row ∈ rows, image row = value := by
  induction rows with
  | nil => exact absurd member List.not_mem_nil
  | cons head rest hypothesis =>
    rw [List.map_cons] at member
    cases List.mem_cons.mp member with
    | inl atHead => exact ⟨head, List.mem_cons_self, atHead.symm⟩
    | inr inRest =>
      obtain ⟨row, rowIn, imaged⟩ := hypothesis inRest
      exact ⟨row, List.mem_cons_of_mem _ rowIn, imaged⟩

/-- Two rows of a list with unique keys are the same row when their keys agree. -/
private theorem eq_of_key_eq {Row : Type} {key : Row → Nat} {rows : List Row}
    {first second : Row} (unique : (rows.map key).Nodup) (firstIn : first ∈ rows)
    (secondIn : second ∈ rows) (same : key first = key second) : first = second := by
  induction rows with
  | nil => exact absurd firstIn List.not_mem_nil
  | cons head rest hypothesis =>
    rw [List.map_cons, List.nodup_cons] at unique
    have apart : ∀ {row : Row}, row ∈ rest → key head ≠ key row :=
      fun member equal => unique.1 (equal ▸ key_mem member)
    cases List.mem_cons.mp firstIn with
    | inl firstHead =>
      cases List.mem_cons.mp secondIn with
      | inl secondHead => exact firstHead.trans secondHead.symm
      | inr secondRest =>
        exact absurd ((congrArg key firstHead).symm.trans same) (apart secondRest)
    | inr firstRest =>
      cases List.mem_cons.mp secondIn with
      | inl secondHead =>
        exact absurd ((congrArg key secondHead).symm.trans same.symm) (apart firstRest)
      | inr secondRest => exact hypothesis unique.2 firstRest secondRest

/-- A replacement of the rows under `id` by a row with the key `id` keeps the keys in order. -/
private theorem map_key_replaced {Row : Type} {key : Row → Nat} {id : Nat} {row : Row}
    (keyed : key row = id) (rows : List Row) :
    (rows.map (fun other => if key other = id then row else other)).map key = rows.map key := by
  induction rows with
  | nil => rfl
  | cons head rest hypothesis =>
    rw [List.map_cons, List.map_cons, List.map_cons, hypothesis]
    by_cases target : key head = id
    · rw [ite_eq_left target, keyed, target]
    · rw [ite_eq_right target]

/-- A filter that drops the rows under a key that no row has keeps every row. -/
private theorem filter_absent {Row : Type} {key : Row → Nat} {id : Nat} {rows : List Row}
    (absent : id ∉ rows.map key) : rows.filter (fun other => key other != id) = rows := by
  induction rows with
  | nil => rfl
  | cons head rest hypothesis =>
    rw [List.map_cons] at absent
    have kept : (key head != id) = true :=
      bne_of_ne fun same => absent (List.mem_cons.mpr (Or.inl same.symm))
    rw [List.filter_cons, ite_eq_left kept,
      hypothesis fun member => absent (List.mem_cons_of_mem _ member)]

/-- A filter that drops the rows under one key erases that key from the keys when the keys are unique. -/
private theorem map_key_removed {Row : Type} {key : Row → Nat} (id : Nat) {rows : List Row}
    (unique : (rows.map key).Nodup) :
    (rows.filter (fun other => key other != id)).map key = (rows.map key).erase id := by
  induction rows with
  | nil => rfl
  | cons head rest hypothesis =>
    rw [List.map_cons, List.nodup_cons] at unique
    by_cases target : key head = id
    · have dropped : ¬(key head != id) = true := not_bne_of_eq target
      have absent : id ∉ rest.map key := target ▸ unique.1
      have found : (id == id) = true := decide_eq_true rfl
      rw [List.filter_cons, ite_eq_right dropped, filter_absent absent, List.map_cons, target,
        List.erase_cons, ite_eq_left found]
    · have kept : (key head != id) = true := bne_of_ne target
      have other : ¬(key head == id) = true := fun equal => target (of_decide_eq_true equal)
      rw [List.filter_cons, ite_eq_left kept, List.map_cons, List.map_cons,
        List.erase_cons_tail other, hypothesis unique.2]

/-- A key that the search for a row under it cannot find lies outside the keys. -/
private theorem absent_of_find? {Row : Type} {key : Row → Nat} {id : Nat} {rows : List Row}
    (unknown : ¬(rows.find? (fun other => key other == id)).isSome = true) :
    id ∉ rows.map key := by
  induction rows with
  | nil => exact List.not_mem_nil
  | cons head rest hypothesis =>
    rw [List.map_cons, List.mem_cons]
    by_cases target : key head = id
    · have passes : (key head == id) = true := decide_eq_true target
      rw [List.find?_cons_of_pos (p := fun other => key other == id) passes] at unknown
      exact (unknown rfl).elim
    · have fails : ¬(key head == id) = true := fun passes => target (of_decide_eq_true passes)
      rw [List.find?_cons_of_neg (p := fun other => key other == id) fails] at unknown
      intro member
      cases member with
      | inl atHead => exact target atHead.symm
      | inr inRest => exact hypothesis unknown inRest

/-- The row that the search under a key finds has that key. -/
private theorem key_of_find? {Row : Type} {key : Row → Nat} {id : Nat} {rows : List Row}
    {row : Row} (found : rows.find? (fun other => key other == id) = some row) : key row = id :=
  have passes := List.find?_some found
  of_decide_eq_true passes

/-- The keys after a command stand as before, or as before with one new key at the end, or as before with one key erased. -/
private theorem order_of_rowsAfter {Row : Type} {key : Row → Nat} {put : Row → Change}
    {before after : List Row} {changes : List Change} (unique : (before.map key).Nodup)
    (rows : RowsAfter key put before changes after) :
    after.map key = before.map key ∨
      (∃ id, id ∉ before.map key ∧ after.map key = before.map key ++ [id]) ∨
      (∃ id, after.map key = (before.map key).erase id) := by
  cases rows with
  | kept => exact Or.inl rfl
  | appended row fresh _ => exact Or.inr (Or.inl ⟨key row, fresh, List.map_append⟩)
  | replaced _ _ keyed _ => exact Or.inl (map_key_replaced keyed before)
  | removed id => exact Or.inr (Or.inr ⟨id, map_key_removed id unique⟩)

/-- A row after a command under the key of a row before it is that row, unless it is the row of the one put that the command returns. -/
private theorem others_of_rowsAfter {Row : Type} {key : Row → Nat} {put : Row → Change}
    {before after : List Row} {changes : List Change} (unique : (before.map key).Nodup)
    (rows : RowsAfter key put before changes after) :
    ∀ row ∈ before, ∀ later ∈ after, key later = key row → later = row ∨ changes = [put later] := by
  intro row rowIn later laterIn same
  cases rows with
  | kept => exact Or.inl (eq_of_key_eq unique laterIn rowIn same)
  | appended _ _ named =>
    cases List.mem_append.mp laterIn with
    | inl old => exact Or.inl (eq_of_key_eq unique old rowIn same)
    | inr new =>
      rw [List.mem_singleton.mp new]
      exact Or.inr named
  | replaced id edited _ named =>
    obtain ⟨other, otherIn, made⟩ := image_of_mem laterIn
    have made : (if key other = id then edited else other) = later := made
    by_cases target : key other = id
    · rw [ite_eq_left target] at made
      subst made
      exact Or.inr named
    · rw [ite_eq_right target] at made
      subst made
      exact Or.inl (eq_of_key_eq unique otherIn rowIn same)
  | removed _ => exact Or.inl (eq_of_key_eq unique (List.mem_filter.mp laterIn).1 rowIn same)

/-- How an accepted command leaves the exercises and the sets of `log`. -/
private structure Shaped (log : Log) (transition : Transition) : Prop where
  exercises :
    RowsAfter (·.id) Change.putExercise log.exercises transition.changes transition.log.exercises
  sets : RowsAfter (·.id) Change.putSet log.sets transition.changes transition.log.sets

/-- Every transition that `outcome` accepts leaves the rows of `log` in a shape. -/
private def Holds (log : Log) (outcome : Outcome) : Prop :=
  ∀ transition, outcome = .accepted transition → Shaped log transition

/-- A refusal carries no transition, so the rule asks nothing of it. -/
private theorem refused_holds {log : Log} {refusal : Refusal} : Holds log (.refused refusal) :=
  fun _ accepted => nomatch accepted

/-- A transition holds when it leaves the rows of `log` in a shape. -/
private theorem accepted_holds {log after : Log} {changes : List Change}
    (shaped : Shaped log ⟨after, changes⟩) : Holds log (.accepted ⟨after, changes⟩) :=
  fun | _, rfl => shaped

/-- A command that changes nothing keeps every row. -/
private theorem unchanged_holds {log : Log} : Holds log (unchanged log) :=
  accepted_holds ⟨.kept, .kept⟩

/-- An `if` holds when its first branch holds and its second branch holds where the condition fails. -/
private theorem ite_holds {log : Log} {condition : Prop} [Decidable condition]
    {first second : Outcome} (whenTrue : Holds log first)
    (whenFalse : ¬condition → Holds log second) :
    Holds log (if condition then first else second) := by
  by_cases passes : condition
  · rw [ite_eq_left passes]
    exact whenTrue
  · rw [ite_eq_right passes]
    exact whenFalse passes

/-- `addExercise` appends an exercise under an identifier that no exercise has and keeps the sets. -/
private theorem addExercise_holds (log : Log) (id : ExerciseID) (name : Name)
    (bodyPart : BodyPart) : Holds log (addExercise log id name bodyPart) :=
  ite_holds refused_holds fun unknown =>
  have fresh : id ∉ log.exercises.map (·.id) := absent_of_find? unknown
  ite_holds refused_holds fun _ =>
  ite_holds (accepted_holds ⟨.appended (⟨id, name, bodyPart, false⟩ : Exercise) fresh rfl, .kept⟩) fun _ =>
  refused_holds

/-- `replaceExercise` keeps every row or replaces the exercise under `id` by an edit that keeps its identifier, and keeps the sets. -/
private theorem replaceExercise_holds {log : Log} {id : ExerciseID}
    {edit : Exercise → Exercise} (keepsID : ∀ exercise, (edit exercise).id = exercise.id) :
    Holds log (replaceExercise log id edit) := by
  unfold replaceExercise
  cases found : log.exercise? id with
  | none => exact refused_holds
  | some current =>
    have named : current.id = id := key_of_find? found
    exact
      ite_holds unchanged_holds fun _ =>
      ite_holds refused_holds fun _ =>
      accepted_holds ⟨.replaced id (edit current) ((keepsID current).trans named) rfl, .kept⟩

/-- `deleteExercise` drops the exercises under `id` and keeps the sets. -/
private theorem deleteExercise_holds (log : Log) (id : ExerciseID) :
    Holds log (deleteExercise log id) :=
  ite_holds refused_holds fun _ =>
  ite_holds refused_holds fun _ =>
  accepted_holds ⟨.removed id, .kept⟩

/-- `logSet` keeps the exercises and appends a set under an identifier that no set has. -/
private theorem logSet_holds (log : Log) (set : LoggedSet) : Holds log (logSet log set) :=
  ite_holds refused_holds fun _ =>
  ite_holds refused_holds fun unknown =>
  have fresh : set.id ∉ log.sets.map (·.id) := absent_of_find? unknown
  ite_holds (accepted_holds ⟨.kept, .appended set fresh rfl⟩) fun _ =>
  refused_holds

/-- `editSet` keeps every row or replaces the set under `id` by an edit that keeps its identifier. -/
private theorem editSet_holds (log : Log) (id : SetID) (weight reps : Nat) :
    Holds log (editSet log id weight reps) := by
  unfold editSet
  cases found : log.set? id with
  | none => exact refused_holds
  | some current =>
    have named : current.id = id := key_of_find? found
    exact
      ite_holds unchanged_holds fun _ =>
      accepted_holds ⟨.kept, .replaced id { current with weight := weight, reps := reps } named rfl⟩

/-- `deleteSet` keeps the exercises and drops the sets under `id`. -/
private theorem deleteSet_holds (log : Log) (id : SetID) : Holds log (deleteSet log id) :=
  ite_holds refused_holds fun _ =>
  accepted_holds ⟨.kept, .removed id⟩

/-- `writeMemo` keeps the exercises and the sets. -/
private theorem writeMemo_holds (log : Log) (day : Day) (memo : Option MemoText) :
    Holds log (writeMemo log day memo) :=
  ite_holds unchanged_holds fun _ =>
  accepted_holds ⟨.kept, .kept⟩

/-- Every command other than a replacement holds from every log.
Each line proves the line of `apply` with the same pattern. -/
private theorem command_holds (log : Log) :
    (command : Command) → (∀ replacement, command ≠ .replaceAll replacement) →
      Holds log (apply log command)
  | .addExercise _ (.refused _) _, _ => refused_holds
  | .addExercise id (.accepted name) bodyPart, _ => addExercise_holds log id name bodyPart
  | .editExercise _ (.refused _) _, _ => refused_holds
  | .editExercise _ (.accepted _) _, _ => replaceExercise_holds fun _ => rfl
  | .setExerciseArchived _ _, _ => replaceExercise_holds fun _ => rfl
  | .deleteExercise id, _ => deleteExercise_holds log id
  | .logSet id exerciseID day weight reps, _ =>
    logSet_holds log ⟨id, exerciseID, day, weight, reps⟩
  | .editSet id weight reps, _ => editSet_holds log id weight reps
  | .deleteSet id, _ => deleteSet_holds log id
  | .writeMemo _ (.refused _), _ => refused_holds
  | .writeMemo day .nothing, _ => writeMemo_holds log day none
  | .writeMemo day (.kept text), _ => writeMemo_holds log day (some text)
  | .replaceAll replacement, edit => absurd rfl (edit replacement)

/-- After an accepted command other than a replacement, the exercise identifiers stand as before, or as before with one new identifier at the end, or as before with one identifier erased.
No command reorders the exercises. -/
theorem apply_keeps_exercise_order {log : Log} {command : Command} {transition : Transition}
    (valid : Valid log) (accepted : apply log command = .accepted transition)
    (edit : ∀ replacement, command ≠ .replaceAll replacement) :
    transition.log.exercises.map (·.id) = log.exercises.map (·.id) ∨
      (∃ id, id ∉ log.exercises.map (·.id) ∧
        transition.log.exercises.map (·.id) = log.exercises.map (·.id) ++ [id]) ∨
      (∃ id, transition.log.exercises.map (·.id) = (log.exercises.map (·.id)).erase id) :=
  order_of_rowsAfter valid.exerciseIDs
    (command_holds log command edit transition accepted).exercises

/-- After an accepted command other than a replacement, the set identifiers stand as before, or as before with one new identifier at the end, or as before with one identifier erased.
No command reorders the sets. -/
theorem apply_keeps_set_order {log : Log} {command : Command} {transition : Transition}
    (valid : Valid log) (accepted : apply log command = .accepted transition)
    (edit : ∀ replacement, command ≠ .replaceAll replacement) :
    transition.log.sets.map (·.id) = log.sets.map (·.id) ∨
      (∃ id, id ∉ log.sets.map (·.id) ∧
        transition.log.sets.map (·.id) = log.sets.map (·.id) ++ [id]) ∨
      (∃ id, transition.log.sets.map (·.id) = (log.sets.map (·.id)).erase id) :=
  order_of_rowsAfter valid.setIDs (command_holds log command edit transition accepted).sets

/-- A row that survives an accepted command other than a replacement is unchanged unless the command returns the put of exactly that row.
No command alters a row that it does not name. -/
theorem apply_keeps_other_rows {log : Log} {command : Command} {transition : Transition}
    (valid : Valid log) (accepted : apply log command = .accepted transition)
    (edit : ∀ replacement, command ≠ .replaceAll replacement) :
    (∀ exercise ∈ log.exercises, ∀ after ∈ transition.log.exercises,
        after.id = exercise.id → after = exercise ∨ transition.changes = [.putExercise after]) ∧
      (∀ set ∈ log.sets, ∀ after ∈ transition.log.sets,
        after.id = set.id → after = set ∨ transition.changes = [.putSet after]) :=
  have shaped := command_holds log command edit transition accepted
  ⟨others_of_rowsAfter valid.exerciseIDs shaped.exercises,
    others_of_rowsAfter valid.setIDs shaped.sets⟩

end Gymemo.Log
