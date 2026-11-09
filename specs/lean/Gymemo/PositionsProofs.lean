import Gymemo.Log
import Gymemo.LogStore
import Gymemo.Positions

/-!
# The rules by positions agree with the model

`Gymemo/Positions.lean` states `TrainingLog.apply`, `TrainingLog.make`, and the row model of the Swift tests line by line from the Swift code.
`Gymemo/Log.lean` states the same rules over identifiers with `find?`, `map`, and `filter`.
This file proves that both statements give the same results on every log that holds the invariants, which is every log the Swift code can build.
The proofs read three of the invariants: exercise identifiers are unique, set identifiers are unique, and the memos lie in the order of their days.
Two examples show that the agreement fails on rows with a repeated identifier.
-/

namespace Gymemo.Log

/-- A log whose two sets share one identifier. -/
private def twinSets : Log :=
  ⟨[⟨0, 0, .chest, false⟩], [⟨0, 0, 0, 0, 0⟩, ⟨0, 0, 0, 1, 1⟩], []⟩

/-- On a log with a repeated set identifier, the rules by positions and the model delete different sets.
The rules by positions remove the set at the last position of the identifier, and the model removes every set with the identifier.
`positions_apply_eq` therefore asks for a log that holds the invariants. -/
private theorem apply_differs_on_twinSets :
    Positions.apply twinSets (.deleteSet 0)
        = .accepted ⟨⟨[⟨0, 0, .chest, false⟩], [⟨0, 0, 0, 0, 0⟩], []⟩, [.removeSet 0]⟩
      ∧ apply twinSets (.deleteSet 0)
        = .accepted ⟨⟨[⟨0, 0, .chest, false⟩], [], []⟩, [.removeSet 0]⟩ := by
  decide

/-- Rows whose two exercises share one identifier. -/
private def twinExercises : Log :=
  ⟨[⟨0, 0, .chest, false⟩, ⟨0, 1, .back, false⟩], [], []⟩

/-- On rows with a repeated exercise identifier, the row model and the model's store write different rows.
The row model writes the first row with the identifier, and the model's store writes every row with the identifier.
`positions_store_eq` therefore asks for rows with unique identifiers. -/
private theorem store_differs_on_twinExercises :
    Positions.storeRow twinExercises (.putExercise ⟨0, 2, .legs, false⟩)
        = ⟨[⟨0, 2, .legs, false⟩, ⟨0, 1, .back, false⟩], [], []⟩
      ∧ store twinExercises (.putExercise ⟨0, 2, .legs, false⟩)
        = ⟨[⟨0, 2, .legs, false⟩, ⟨0, 2, .legs, false⟩], [], []⟩ := by
  decide

/-- In a list with unique keys, no row after the first has the key of the first, and the rest has unique keys. -/
private theorem unique_cons {Row : Type} {key : Row → Nat} {first : Row} {rest : List Row}
    (unique : ((first :: rest).map key).Nodup) :
    (∀ row ∈ rest, key row ≠ key first) ∧ (rest.map key).Nodup := by
  have parts := List.nodup_cons.mp (show (key first :: rest.map key).Nodup from unique)
  exact ⟨fun row member same => parts.1 (same ▸ List.mem_map_of_mem member), parts.2⟩

/-- Over rows that the test refuses, the loop of `lastPosition` keeps the position it knows. -/
private theorem lastPosition_refused {Row : Type} {found : Row → Bool} :
    ∀ {rows : List Row} {position : Nat} {known : Option Nat},
      (∀ row ∈ rows, found row = false) → Positions.lastPosition found rows position known = known
  | [], _, _, _ => rfl
  | row :: rest, _, _, refused => by
    rw [Positions.lastPosition, refused row List.mem_cons_self]
    exact lastPosition_refused fun other member => refused other (List.mem_cons_of_mem row member)

/-- With unique keys, the position that `lastPosition` gives for a key is the position where `findIdx?` stops, counted from `start`. -/
private theorem lastPosition_eq_findIdx? {Row : Type} {key : Row → Nat} {id : Nat} :
    ∀ {rows : List Row} {start : Nat}, (rows.map key).Nodup →
      Positions.lastPosition (fun row => key row == id) rows start none
        = (rows.findIdx? (fun row => key row == id)).map (· + start)
  | [], _, _ => rfl
  | first :: rest, start, unique => by
    obtain ⟨differ, restUnique⟩ := unique_cons unique
    rw [Positions.lastPosition, List.findIdx?_cons]
    cases hit : key first == id with
    | true =>
      have named : key first = id := beq_iff_eq.mp hit
      have refused : ∀ row ∈ rest, (key row == id) = false := fun row member =>
        beq_eq_false_iff_ne.mpr (named ▸ differ row member)
      rw [lastPosition_refused refused]
      exact congrArg some (Nat.zero_add start).symm
    | false =>
      refine (lastPosition_eq_findIdx? restUnique).trans ?_
      cases rest.findIdx? (fun row => key row == id) with
      | none => rfl
      | some index => exact congrArg some (Nat.add_right_comm index 1 start).symm

/-- With unique keys, `lastPosition` from the first position gives what `findIdx?` gives. -/
private theorem lastPosition_zero {Row : Type} {key : Row → Nat} {id : Nat} {rows : List Row}
    (unique : (rows.map key).Nodup) :
    Positions.lastPosition (fun row => key row == id) rows 0 none
      = rows.findIdx? (fun row => key row == id) := by
  rw [lastPosition_eq_findIdx? unique]
  cases rows.findIdx? (fun row => key row == id) with
  | none => rfl
  | some _ => rfl

/-- `find?` gives the row at the position where `findIdx?` stops. -/
private theorem find?_eq_findIdx?_bind {Row : Type} {found : Row → Bool} :
    ∀ {rows : List Row}, rows.find? found = (rows.findIdx? found).bind (fun index => rows[index]?)
  | [] => rfl
  | first :: rest => by
    rw [List.find?_cons, List.findIdx?_cons]
    cases found first with
    | true => rfl
    | false =>
      refine (find?_eq_findIdx?_bind (rows := rest)).trans ?_
      cases rest.findIdx? found with
      | none => rfl
      | some _ => rfl

/-- The position where `findIdx?` stops holds a row that passes the test. -/
private theorem findIdx?_found {Row : Type} {found : Row → Bool} :
    ∀ {rows : List Row} {index : Nat}, rows.findIdx? found = some index →
      ∃ row, rows[index]? = some row ∧ found row = true
  | [], _, search => nomatch search
  | first :: rest, _, search => by
    rw [List.findIdx?_cons] at search
    cases passes : found first with
    | true =>
      rw [passes] at search
      cases search
      exact ⟨first, rfl, passes⟩
    | false =>
      rw [passes] at search
      cases later : rest.findIdx? found with
      | none =>
        rw [later] at search
        cases search
      | some _ =>
        rw [later] at search
        cases search
        exact findIdx?_found (rows := rest) later

/-- When `findIdx?` stops, some row passes the test. -/
private theorem any_of_findIdx?_some {Row : Type} {found : Row → Bool} {rows : List Row}
    {index : Nat} (search : rows.findIdx? found = some index) : rows.any found = true := by
  obtain ⟨row, located, passes⟩ := findIdx?_found search
  exact List.any_eq_true.mpr ⟨row, List.mem_of_getElem? located, passes⟩

/-- When `findIdx?` finds nothing, no row passes the test. -/
private theorem any_of_findIdx?_none {Row : Type} {found : Row → Bool} {rows : List Row}
    (search : rows.findIdx? found = none) : rows.any found = false :=
  List.any_eq_false.mpr fun row member => by
    rw [List.findIdx?_eq_none_iff.mp search row member]
    exact Bool.false_ne_true

/-- Rows whose keys all differ from `id` stay as they are under the map that replaces the rows with `id`. -/
private theorem map_replace_absent {Row : Type} {key : Row → Nat} {id : Nat} {edited : Row}
    {rows : List Row} (absent : ∀ row ∈ rows, key row ≠ id) :
    rows.map (fun row => if key row = id then edited else row) = rows :=
  (List.map_congr_left fun row member => ite_eq_right (absent row member)).trans (List.map_id' rows)

/-- Rows whose keys all differ from `id` all pass the filter that removes the rows with `id`. -/
private theorem filter_remove_absent {Row : Type} {key : Row → Nat} {id : Nat} {rows : List Row}
    (absent : ∀ row ∈ rows, key row ≠ id) : rows.filter (fun row => key row != id) = rows :=
  List.filter_eq_self.mpr fun row member => bne_iff_ne.mpr (absent row member)

/-- With unique keys, writing a row at the position where `findIdx?` stops for `id` replaces every row with `id`. -/
private theorem set_eq_map_replace {Row : Type} {key : Row → Nat} {id : Nat} {edited : Row} :
    ∀ {rows : List Row} {index : Nat}, (rows.map key).Nodup →
      rows.findIdx? (fun row => key row == id) = some index →
      rows.set index edited = rows.map (fun row => if key row = id then edited else row)
  | [], _, _, search => nomatch search
  | first :: rest, index, unique, search => by
    obtain ⟨differ, restUnique⟩ := unique_cons unique
    rw [List.findIdx?_cons] at search
    cases hit : key first == id with
    | true =>
      have named : key first = id := beq_iff_eq.mp hit
      rw [hit] at search
      cases search
      rw [List.set_cons_zero, List.map_cons, ite_eq_left named,
        map_replace_absent (named ▸ differ)]
    | false =>
      have other : key first ≠ id := beq_eq_false_iff_ne.mp hit
      rw [hit] at search
      cases later : rest.findIdx? (fun row => key row == id) with
      | none =>
        rw [later] at search
        cases search
      | some position =>
        rw [later] at search
        cases search
        rw [List.set_cons_succ, List.map_cons, ite_eq_right other,
          set_eq_map_replace restUnique later]

/-- With unique keys, removing the row at the position where `findIdx?` stops for `id` removes every row with `id`. -/
private theorem eraseIdx_eq_filter_remove {Row : Type} {key : Row → Nat} {id : Nat} :
    ∀ {rows : List Row} {index : Nat}, (rows.map key).Nodup →
      rows.findIdx? (fun row => key row == id) = some index →
      rows.eraseIdx index = rows.filter (fun row => key row != id)
  | [], _, _, search => nomatch search
  | first :: rest, index, unique, search => by
    obtain ⟨differ, restUnique⟩ := unique_cons unique
    rw [List.findIdx?_cons] at search
    cases hit : key first == id with
    | true =>
      have named : key first = id := beq_iff_eq.mp hit
      rw [hit] at search
      cases search
      rw [List.eraseIdx_cons_zero,
        List.filter_cons_of_neg (p := fun row => key row != id)
          (fun kept => bne_iff_ne.mp kept named),
        filter_remove_absent (named ▸ differ)]
    | false =>
      have other : key first ≠ id := beq_eq_false_iff_ne.mp hit
      rw [hit] at search
      cases later : rest.findIdx? (fun row => key row == id) with
      | none =>
        rw [later] at search
        cases search
      | some position =>
        rw [later] at search
        cases search
        rw [List.eraseIdx_cons_succ,
          List.filter_cons_of_pos (p := fun row => key row != id) (bne_iff_ne.mpr other),
          eraseIdx_eq_filter_remove restUnique later]

/-- A filter keeps no row exactly when no row passes it. -/
private theorem isEmpty_filter {Row : Type} {found : Row → Bool} :
    ∀ {rows : List Row}, (rows.filter found).isEmpty = !rows.any found
  | [] => rfl
  | first :: rest => by
    rw [List.filter_cons, List.any_cons]
    cases found first with
    | true => rfl
    | false => exact isEmpty_filter

/-- An `if` on the negation of a decision is the `if` on the condition with its branches swapped. -/
private theorem ite_not_decide {condition : Prop} [Decidable condition] {α : Type} {x y : α} :
    (if (!decide condition) = true then x else y) = (if condition then y else x) := by
  by_cases holds : condition
  · rw [decide_eq_true holds, ite_eq_left holds]
    exact ite_eq_right Bool.false_ne_true
  · rw [decide_eq_false holds, ite_eq_right holds]
    exact ite_eq_left rfl

/-- In memos ordered by day, every memo after the first lies on a later day, and the rest stays ordered. -/
private theorem ordered_cons {first : Day × MemoText} {rest : List (Day × MemoText)}
    (ordered : ((first :: rest).map (·.1)).Pairwise (· < ·)) :
    (∀ entry ∈ rest, first.1 < entry.1) ∧ (rest.map (·.1)).Pairwise (· < ·) := by
  have parts :=
    List.pairwise_cons.mp (show (first.1 :: rest.map (·.1)).Pairwise (· < ·) from ordered)
  exact ⟨fun entry member => parts.1 entry.1 (List.mem_map_of_mem member), parts.2⟩

/-- Removing a day before every day of the memos leaves the memos as they are. -/
private theorem without_earlier {memos : List (Day × MemoText)} {day : Day}
    (later : ∀ entry ∈ memos, day < entry.1) : Positions.without memos day = memos :=
  List.filter_eq_self.mpr fun entry member => bne_iff_ne.mpr (Int.ne_of_gt (later entry member))

/-- Removing the day of the first memo drops that memo. -/
private theorem without_cons_same {day : Day} {kept : MemoText} {rest : List (Day × MemoText)} :
    Positions.without ((day, kept) :: rest) day = Positions.without rest day :=
  List.filter_cons_of_neg (p := fun entry : Day × MemoText => !(entry.1 == day)) fun removed =>
    bne_iff_ne.mp removed rfl

/-- Removing another day than the day of the first memo keeps that memo. -/
private theorem without_cons_other {day : Day} {entry : Day × MemoText}
    {rest : List (Day × MemoText)} (other : entry.1 ≠ day) :
    Positions.without (entry :: rest) day = entry :: Positions.without rest day :=
  List.filter_cons_of_pos (p := fun entry : Day × MemoText => !(entry.1 == day))
    (bne_iff_ne.mpr other)

/-- A memo on a day before every day of the memos goes in front of them. -/
private theorem placed_earlier {entry : Day × MemoText} {memos : List (Day × MemoText)}
    (later : ∀ other ∈ memos, entry.1 < other.1) :
    Positions.placed entry memos = entry :: memos := by
  cases memos with
  | nil => rfl
  | cons first rest =>
    rw [Positions.placed, ite_eq_left (Int.le_of_lt (later first List.mem_cons_self))]

/-- On memos ordered by day, placing a text after removing its day gives what `insertMemo` gives. -/
private theorem placed_without {day : Day} {text : MemoText} :
    ∀ {memos : List (Day × MemoText)}, (memos.map (·.1)).Pairwise (· < ·) →
      Positions.placed (day, text) (Positions.without memos day) = insertMemo memos day text
  | [], _ => rfl
  | (first, kept) :: rest, ordered => by
    obtain ⟨later, restOrdered⟩ := ordered_cons ordered
    rw [insertMemo]
    rcases Int.lt_trichotomy day first with before | same | after
    · have allLater : ∀ entry ∈ (first, kept) :: rest, day < entry.1 := fun entry member =>
        match List.mem_cons.mp member with
        | .inl head => head ▸ before
        | .inr tail => Int.lt_trans before (later entry tail)
      rw [ite_eq_left before, without_earlier allLater,
        placed_earlier (entry := (day, text)) allLater]
    · subst first
      rw [ite_eq_right (Int.lt_irrefl day), ite_eq_left rfl, without_cons_same,
        without_earlier later, placed_earlier (entry := (day, text)) later]
    · rw [ite_eq_right (Int.not_lt.mpr (Int.le_of_lt after)), ite_eq_right (Int.ne_of_gt after),
        without_cons_other (Int.ne_of_lt after), Positions.placed,
        ite_eq_right (Int.not_le.mpr after), placed_without restOrdered]

/-- On memos ordered by day, the dictionary assignment of the Swift code gives what `writeMemos` gives. -/
private theorem assigned_eq_writeMemos {memos : List (Day × MemoText)} {day : Day}
    (ordered : (memos.map (·.1)).Pairwise (· < ·)) :
    ∀ memo, Positions.assigned memos day memo = writeMemos memos day memo
  | none => rfl
  | some _ => placed_without ordered

/-- With unique exercise identifiers, `Positions.exercise` finds what the model's search finds. -/
private theorem exercise_eq_exercise? {log : Log} {id : ExerciseID}
    (unique : (log.exercises.map (·.id)).Nodup) : Positions.exercise log id = log.exercise? id := by
  unfold Positions.exercise Positions.exercisePosition Log.exercise?
  rw [lastPosition_zero unique, find?_eq_findIdx?_bind]

/-- With unique set identifiers, `Positions.set` finds what the model's search finds. -/
private theorem set_eq_set? {log : Log} {id : SetID} (unique : (log.sets.map (·.id)).Nodup) :
    Positions.set log id = log.set? id := by
  unfold Positions.set Positions.setPosition Log.set?
  rw [lastPosition_zero unique, find?_eq_findIdx?_bind]

/-- `addExercise` by positions refuses and accepts as the model does. -/
private theorem addExercise_eq {log : Log} {id : ExerciseID} {name : Name} {bodyPart : BodyPart}
    (unique : (log.exercises.map (·.id)).Nodup) :
    Positions.addExercise log id name bodyPart = addExercise log id name bodyPart := by
  unfold Positions.addExercise addExercise
  rw [exercise_eq_exercise? unique, ite_not_decide]

/-- `replaceExercise` by positions writes at the only position of the identifier, which replaces every row with it. -/
private theorem replaceExercise_eq {log : Log} {id : ExerciseID} {edit : Exercise → Exercise}
    (unique : (log.exercises.map (·.id)).Nodup) :
    Positions.replaceExercise log id edit = replaceExercise log id edit := by
  unfold Positions.replaceExercise replaceExercise Positions.exercisePosition Log.exercise?
  rw [lastPosition_zero unique, find?_eq_findIdx?_bind]
  cases search : log.exercises.findIdx? (fun row => row.id == id) with
  | none => rfl
  | some index =>
    dsimp only [Option.bind_some]
    cases log.exercises[index]? with
    | none => rfl
    | some _ =>
      dsimp only
      rw [set_eq_map_replace unique search]

/-- `deleteExercise` by positions removes the row at the only position of the identifier, which removes every row with it. -/
private theorem deleteExercise_eq {log : Log} {id : ExerciseID}
    (unique : (log.exercises.map (·.id)).Nodup) :
    Positions.deleteExercise log id = deleteExercise log id := by
  unfold Positions.deleteExercise deleteExercise Positions.exercisePosition Log.exercise?
    Positions.setsOf
  rw [lastPosition_zero unique, find?_eq_findIdx?_bind, isEmpty_filter, Bool.not_not]
  cases search : log.exercises.findIdx? (fun row => row.id == id) with
  | none => rfl
  | some index =>
    obtain ⟨_, found, _⟩ := findIdx?_found search
    dsimp only
    rw [Option.bind_some, found, Option.isNone_some, ite_eq_right Bool.false_ne_true,
      eraseIdx_eq_filter_remove unique search]

/-- `logSet` by positions refuses and accepts as the model does. -/
private theorem logSet_eq {log : Log} {row : LoggedSet} (valid : Valid log) :
    Positions.logSet log row = logSet log row := by
  unfold Positions.logSet logSet
  rw [exercise_eq_exercise? valid.exerciseIDs, set_eq_set? valid.setIDs, ite_not_decide]

/-- `editSet` by positions writes at the only position of the identifier, which replaces every row with it. -/
private theorem editSet_eq {log : Log} {id : SetID} {weight reps : Nat}
    (unique : (log.sets.map (·.id)).Nodup) :
    Positions.editSet log id weight reps = editSet log id weight reps := by
  unfold Positions.editSet editSet Positions.setPosition Log.set?
  rw [lastPosition_zero unique, find?_eq_findIdx?_bind]
  cases search : log.sets.findIdx? (fun row => row.id == id) with
  | none => rfl
  | some index =>
    dsimp only [Option.bind_some]
    cases log.sets[index]? with
    | none => rfl
    | some _ =>
      dsimp only
      rw [set_eq_map_replace unique search]

/-- `deleteSet` by positions removes the row at the only position of the identifier, which removes every row with it. -/
private theorem deleteSet_eq {log : Log} {id : SetID} (unique : (log.sets.map (·.id)).Nodup) :
    Positions.deleteSet log id = deleteSet log id := by
  unfold Positions.deleteSet deleteSet Positions.setPosition Log.set?
  rw [lastPosition_zero unique, find?_eq_findIdx?_bind]
  cases search : log.sets.findIdx? (fun row => row.id == id) with
  | none => rfl
  | some index =>
    obtain ⟨_, found, _⟩ := findIdx?_found search
    dsimp only
    rw [Option.bind_some, found, Option.isNone_some, ite_eq_right Bool.false_ne_true,
      eraseIdx_eq_filter_remove unique search]

/-- `writeMemo` by positions reads and assigns the dictionary as the model reads and writes its ordered list. -/
private theorem writeMemo_eq {log : Log} {day : Day} {memo : Option MemoText}
    (ordered : (log.memos.map (·.1)).Pairwise (· < ·)) :
    Positions.writeMemo log day memo = writeMemo log day memo := by
  unfold Positions.writeMemo writeMemo
  rw [assigned_eq_writeMemos ordered]
  rfl

/-- On a log that holds the invariants, the rules by positions give what the model gives: the same refusal, or the same new log with the same changes.
Each line proves the line of `apply` with the same pattern. -/
theorem positions_apply_eq {log : Log} {command : Command} (valid : Valid log) :
    Positions.apply log command = apply log command :=
  match command with
  | .addExercise _ (.refused _) _ => rfl
  | .addExercise _ (.accepted _) _ => addExercise_eq valid.exerciseIDs
  | .editExercise _ (.refused _) _ => rfl
  | .editExercise _ (.accepted _) _ => replaceExercise_eq valid.exerciseIDs
  | .setExerciseArchived _ _ => replaceExercise_eq valid.exerciseIDs
  | .deleteExercise _ => deleteExercise_eq valid.exerciseIDs
  | .logSet _ _ _ _ _ => logSet_eq valid
  | .editSet _ _ _ => editSet_eq valid.setIDs
  | .deleteSet _ => deleteSet_eq valid.setIDs
  | .writeMemo _ (.refused _) => rfl
  | .writeMemo _ .nothing => writeMemo_eq valid.memoDays
  | .writeMemo _ (.kept _) => writeMemo_eq valid.memoDays
  | .replaceAll _ => rfl

/-- On rows with unique identifiers and memos ordered by day, the row model of the Swift tests gives what the model's store gives.
A put finds at most one row with the identifier, so writing the first such row replaces every such row. -/
theorem positions_store_eq {rows : Log} {change : Change}
    (exercises : (rows.exercises.map (·.id)).Nodup) (sets : (rows.sets.map (·.id)).Nodup)
    (memos : (rows.memos.map (·.1)).Pairwise (· < ·)) :
    Positions.storeRow rows change = store rows change := by
  cases change with
  | putExercise exercise =>
    rw [Positions.storeRow, store, putExercise]
    cases search : rows.exercises.findIdx? (fun row => row.id == exercise.id) with
    | none =>
      rw [any_of_findIdx?_none search, ite_eq_right Bool.false_ne_true]
    | some index =>
      dsimp only
      rw [any_of_findIdx?_some search, ite_eq_left (rfl : true = true),
        set_eq_map_replace exercises search]
  | removeExercise _ => rfl
  | putSet set =>
    rw [Positions.storeRow, store, putSet]
    cases search : rows.sets.findIdx? (fun row => row.id == set.id) with
    | none =>
      rw [any_of_findIdx?_none search, ite_eq_right Bool.false_ne_true]
    | some index =>
      dsimp only
      rw [any_of_findIdx?_some search, ite_eq_left (rfl : true = true),
        set_eq_map_replace sets search]
  | removeSet _ => rfl
  | putMemo _ _ => exact congrArg (fun kept => { rows with memos := kept }) (placed_without memos)
  | removeMemo _ => rfl
  | replaceAll _ => rfl

/-- The first loop of `TrainingLog.make` refuses rows exactly where `checkExercises` refuses them. -/
private theorem checkExercises_eq :
    ∀ {rows : List Exercise} {ids : List ExerciseID} {names : List Name},
      checkExercises rows ids names
        = match Positions.readExercises rows ids names with
          | .error refusal => some refusal
          | .ok _ => none
  | [], _, _ => rfl
  | row :: rest, ids, names => by
    rw [checkExercises, Positions.readExercises]
    cases ids.contains row.id with
    | true => rfl
    | false =>
      cases names.contains row.name with
      | true => rfl
      | false => exact checkExercises_eq

/-- The identifiers that the first loop of `TrainingLog.make` collects hold an identifier exactly when the identifiers it started with or the rows it read hold it. -/
private theorem readExercises_contains :
    ∀ {rows : List Exercise} {ids : List ExerciseID} {names : List Name} {found : List ExerciseID},
      Positions.readExercises rows ids names = .ok found →
        ∀ id, found.contains id = (ids.contains id || rows.any (fun row => row.id == id))
  | [], _, _, _, read, id => by
    cases read
    rw [List.any_nil, Bool.or_false]
  | row :: rest, ids, names, found, read, id => by
    rw [Positions.readExercises] at read
    cases fresh : ids.contains row.id with
    | true =>
      rw [fresh] at read
      cases read
    | false =>
      cases unnamed : names.contains row.name with
      | true =>
        rw [fresh, unnamed] at read
        cases read
      | false =>
        rw [fresh, unnamed] at read
        rw [readExercises_contains read id, List.contains_cons, List.any_cons,
          Bool.beq_comm (a := row.id), Bool.or_assoc, Bool.or_left_comm]

/-- The second loop of `TrainingLog.make` gives what `checkSets` gives when its identifiers hold exactly the identifiers of the exercises. -/
private theorem readSets_eq {exerciseIDs : List ExerciseID} {exercises : List Exercise}
    (same : ∀ id, exerciseIDs.contains id = exercises.any (fun exercise => exercise.id == id)) :
    ∀ {sets : List LoggedSet} {ids : List SetID},
      Positions.readSets exerciseIDs sets ids = checkSets exercises sets ids
  | [], _ => rfl
  | row :: rest, ids => by
    rw [Positions.readSets, checkSets, same row.exerciseID]
    cases ids.contains row.id with
    | true => rfl
    | false =>
      cases exercises.any (fun exercise => exercise.id == row.exerciseID) with
      | true => exact readSets_eq same
      | false => rfl

/-- An `if` on the negation of `a ≤ b` is the `if` on `b < a`. -/
private theorem ite_not_decide_le {a b : Nat} {α : Type} {x y : α} :
    (if (!decide (a ≤ b)) = true then x else y) = (if b < a then x else y) := by
  by_cases within : a ≤ b
  · rw [decide_eq_true within, ite_eq_right (Nat.not_lt.mpr within)]
    exact ite_eq_right Bool.false_ne_true
  · rw [decide_eq_false within, ite_eq_left (Nat.not_le.mp within)]
    exact ite_eq_left rfl

/-- The two statements of `TrainingLog.make` give the same refusal, or none, on every row list.
Both check the counts, then the exercises in order, then the sets in order, and the identifiers that the first loop collects hold exactly the identifiers of the exercises. -/
theorem positions_make_eq {rows : Log} : Positions.make rows = make rows := by
  unfold Positions.make make
  rw [ite_not_decide_le, ite_not_decide_le, checkExercises_eq]
  cases read : Positions.readExercises rows.exercises [] [] with
  | error _ => rfl
  | ok _ =>
    dsimp only
    rw [readSets_eq (readExercises_contains read)]

/-- An outcome that returns at most one change when it is accepted. -/
private def AtMostOne (outcome : Outcome) : Prop :=
  ∀ transition, outcome = .accepted transition → transition.changes.length ≤ 1

/-- A refusal carries no transition. -/
private theorem refused_atMostOne {refusal : Refusal} : AtMostOne (.refused refusal) :=
  fun _ accepted => nomatch accepted

/-- A transition with one change returns one change. -/
private theorem single_atMostOne {log : Log} {change : Change} :
    AtMostOne (.accepted ⟨log, [change]⟩) :=
  fun | _, rfl => Nat.le_refl 1

/-- A command that changes nothing returns no change. -/
private theorem unchanged_atMostOne {log : Log} : AtMostOne (unchanged log) :=
  fun | _, rfl => Nat.zero_le 1

/-- An `if` returns at most one change when both of its branches do. -/
private theorem ite_atMostOne {condition : Prop} [Decidable condition] {first second : Outcome}
    (whenTrue : AtMostOne first) (whenFalse : AtMostOne second) :
    AtMostOne (if condition then first else second) := by
  by_cases holds : condition
  · rw [ite_eq_left holds]
    exact whenTrue
  · rw [ite_eq_right holds]
    exact whenFalse

/-- `replaceExercise` returns no change or one put. -/
private theorem replaceExercise_atMostOne {log : Log} {id : ExerciseID}
    {edit : Exercise → Exercise} : AtMostOne (replaceExercise log id edit) := by
  unfold replaceExercise
  cases log.exercise? id with
  | none => exact refused_atMostOne
  | some _ =>
    exact ite_atMostOne unchanged_atMostOne (ite_atMostOne refused_atMostOne single_atMostOne)

/-- `editSet` returns no change or one put. -/
private theorem editSet_atMostOne {log : Log} {id : SetID} {weight reps : Nat} :
    AtMostOne (editSet log id weight reps) := by
  unfold editSet
  cases log.set? id with
  | none => exact refused_atMostOne
  | some _ => exact ite_atMostOne unchanged_atMostOne single_atMostOne

/-- `writeMemo` returns no change or one put or removal. -/
private theorem writeMemo_atMostOne {log : Log} {day : Day} {memo : Option MemoText} :
    AtMostOne (writeMemo log day memo) :=
  ite_atMostOne unchanged_atMostOne single_atMostOne

/-- Every command returns at most one change.
Each line proves the line of `apply` with the same pattern. -/
private theorem apply_atMostOne (log : Log) : (command : Command) → AtMostOne (apply log command)
  | .addExercise _ (.refused _) _ => refused_atMostOne
  | .addExercise _ (.accepted _) _ =>
    ite_atMostOne refused_atMostOne <| ite_atMostOne refused_atMostOne <|
      ite_atMostOne single_atMostOne refused_atMostOne
  | .editExercise _ (.refused _) _ => refused_atMostOne
  | .editExercise _ (.accepted _) _ => replaceExercise_atMostOne
  | .setExerciseArchived _ _ => replaceExercise_atMostOne
  | .deleteExercise _ =>
    ite_atMostOne refused_atMostOne <| ite_atMostOne refused_atMostOne single_atMostOne
  | .logSet _ _ _ _ _ =>
    ite_atMostOne refused_atMostOne <| ite_atMostOne refused_atMostOne <|
      ite_atMostOne single_atMostOne refused_atMostOne
  | .editSet _ _ _ => editSet_atMostOne
  | .deleteSet _ => ite_atMostOne refused_atMostOne single_atMostOne
  | .writeMemo _ (.refused _) => refused_atMostOne
  | .writeMemo _ .nothing => writeMemo_atMostOne
  | .writeMemo _ (.kept _) => writeMemo_atMostOne
  | .replaceAll _ => single_atMostOne

/-- On rows with unique identifiers and memos ordered by day, the row model and the model's store agree on at most one change. -/
private theorem storeRows_eq_storeAll {rows : Log} {changes : List Change}
    (few : changes.length ≤ 1) (exercises : (rows.exercises.map (·.id)).Nodup)
    (sets : (rows.sets.map (·.id)).Nodup) (memos : (rows.memos.map (·.1)).Pairwise (· < ·)) :
    Positions.storeRows rows changes = storeAll rows changes :=
  match changes, few with
  | [], _ => rfl
  | [_], _ => positions_store_eq exercises sets memos
  | _ :: _ :: _, few => absurd (Nat.le_of_succ_le_succ few) (Nat.not_succ_le_zero _)

/-- The contract between the core and the store, stated on the Swift side.
The rules by positions find a row by its last position and the row model writes the first row with the identifier, yet on a log that holds the invariants the changes of an accepted command still rebuild the new log.
The rules by positions give what the model gives, the command returns at most one change, the row model writes that change as the model's store does, and `apply_rebuilds` finishes the proof. -/
theorem positions_rebuilds {log : Log} {command : Command} {transition : Transition}
    (valid : Valid log) (accepted : Positions.apply log command = .accepted transition) :
    Positions.storeRows log transition.changes = transition.log := by
  have modelAccepted : apply log command = .accepted transition :=
    (positions_apply_eq valid).symm.trans accepted
  rw [storeRows_eq_storeAll (apply_atMostOne log command transition modelAccepted)
    valid.exerciseIDs valid.setIDs valid.memoDays]
  exact apply_rebuilds valid modelAccepted

end Gymemo.Log
