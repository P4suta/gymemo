import Gymemo.Log

/-!
# The invariants of the training log

`Gymemo/Log.lean` states how a command changes the log and which invariants a log holds.
This file proves that the empty log holds the invariants and that every accepted command keeps them.
It also proves that `make` accepts exactly the rows that hold them, and that a transition without changes returns the same log.
For each command, one lemma states what its acceptance did, and a second one derives the invariants from that.
Lean's library proves many facts about lists with `propext` and `Quot.sound`, so this file proves the facts it needs by recursion on the list.
Its theorems then rest on `propext` alone, and only through the order of the days.
-/

namespace Gymemo.Log

variable {α β κ : Type}

/-! ## Lists -/

/-- A property holds for every image of a list exactly when it holds for the image of every element. -/
private theorem forall_mem_map {f : α → β} {P : β → Prop} :
    ∀ {l : List α}, (∀ b ∈ l.map f, P b) ↔ ∀ a ∈ l, P (f a)
  | [] => ⟨fun _ => nofun, fun _ => nofun⟩
  | _ :: _ =>
    List.forall_mem_cons.trans <|
      (and_congr_right fun _ => forall_mem_map).trans
        (List.forall_mem_cons (p := fun a => P (f a))).symm

/-- The image of an element lies among the images of its list. -/
private theorem mem_map_of_mem {f : α → β} {a : α} {l : List α} (member : a ∈ l) :
    f a ∈ l.map f :=
  forall_mem_map.mp (fun _ image => image) a member

/-- A relation holds pairwise on the images of a list exactly when the relation of the images holds pairwise on the list. -/
private theorem pairwise_map {f : α → β} {R : β → β → Prop} :
    ∀ {l : List α}, (l.map f).Pairwise R ↔ l.Pairwise fun a b => R (f a) (f b)
  | [] => ⟨fun _ => .nil, fun _ => .nil⟩
  | _ :: _ =>
    List.pairwise_cons.trans <|
      (and_congr forall_mem_map pairwise_map).trans
        (List.pairwise_cons (R := fun a b => R (f a) (f b))).symm

/-- Two relations hold pairwise together on a list when each of them does. -/
private theorem pairwise_and {R S : α → α → Prop} :
    ∀ {l : List α}, l.Pairwise R → l.Pairwise S → l.Pairwise fun a b => R a b ∧ S a b
  | [], _, _ => .nil
  | _ :: _, .cons headR tailR, .cons headS tailS =>
    .cons (fun b member => ⟨headR b member, headS b member⟩) (pairwise_and tailR tailS)

/-- A list of images is as long as the list. -/
private theorem length_map (f : α → β) : ∀ l : List α, (l.map f).length = l.length
  | [] => rfl
  | _ :: l => congrArg (· + 1) (length_map f l)

/-- The elements that pass a test lie in the list in the same order. -/
private theorem filter_sublist (p : α → Bool) : ∀ l : List α, (l.filter p).Sublist l
  | [] => .slnil
  | a :: l => by
    by_cases pass : p a = true
    · rw [List.filter_cons_of_pos pass]
      exact (filter_sublist p l).cons_cons a
    · rw [List.filter_cons_of_neg pass]
      exact (filter_sublist p l).cons a

/-- An element that passes a test stays among the elements that pass it. -/
private theorem mem_filter_of_mem {p : α → Bool} {a : α} :
    ∀ {l : List α}, a ∈ l → p a = true → a ∈ l.filter p
  | b :: _, member, pass => by
    by_cases passB : p b = true
    · rw [List.filter_cons_of_pos passB]
      cases member with
      | head => exact .head _
      | tail _ member => exact .tail _ (mem_filter_of_mem member pass)
    · rw [List.filter_cons_of_neg passB]
      cases member with
      | head => exact absurd pass passB
      | tail _ member => exact mem_filter_of_mem member pass

/-- A relation that holds pairwise on the images of a list, such as the difference that `Nodup` asks for, holds pairwise on the images of the elements that pass a test. -/
private theorem pairwise_map_filter {f : α → β} {R : β → β → Prop} (p : α → Bool) {l : List α}
    (pairwise : (l.map f).Pairwise R) : ((l.filter p).map f).Pairwise R :=
  pairwise_map.mpr ((pairwise_map.mp pairwise).sublist (filter_sublist p l))

/-- A list with one more element at its end is one element longer. -/
private theorem length_append_singleton (a : α) : ∀ l : List α, (l ++ [a]).length = l.length + 1
  | [] => rfl
  | _ :: l => congrArg (· + 1) (length_append_singleton a l)

/-- A property of every element of a list and of a new element holds for every element once the new one joins the end. -/
private theorem forall_mem_append_singleton {P : α → Prop} {a : α} :
    ∀ {l : List α}, (∀ x ∈ l, P x) → P a → ∀ x ∈ l ++ [a], P x
  | [], _, new => List.forall_mem_cons.mpr ⟨new, nofun⟩
  | _ :: _, old, new =>
    have ⟨head, tail⟩ := List.forall_mem_cons.mp old
    List.forall_mem_cons.mpr ⟨head, forall_mem_append_singleton tail new⟩

/-- A relation holds pairwise on a list with a new element at its end when it holds pairwise on the list and from each of its elements to the new one. -/
private theorem pairwise_append_singleton {R : α → α → Prop} {a : α} :
    ∀ {l : List α}, l.Pairwise R → (∀ x ∈ l, R x a) → (l ++ [a]).Pairwise R
  | [], _, _ => List.pairwise_cons.mpr ⟨nofun, .nil⟩
  | _ :: _, pairwise, toNew =>
    have ⟨head, tail⟩ := List.pairwise_cons.mp pairwise
    have ⟨headNew, tailNew⟩ := List.forall_mem_cons.mp toNew
    List.pairwise_cons.mpr
      ⟨forall_mem_append_singleton head headNew, pairwise_append_singleton tail tailNew⟩

/-- The images of a list stay without repetition when an element with a new image joins the end. -/
private theorem nodup_map_append_singleton {f : α → β} {a : α} {l : List α}
    (nodup : (l.map f).Nodup) (new : ∀ x ∈ l, f x ≠ f a) : ((l ++ [a]).map f).Nodup :=
  pairwise_map.mpr (pairwise_append_singleton (pairwise_map.mp nodup) new)

/-! ## The replacement of the row of one key -/

/-- A row keeps its key when a row of the same key replaces it. -/
private theorem key_replace [DecidableEq κ] {key : α → κ} {wanted : κ} {new : α}
    (same : key new = wanted) (row : α) :
    key (if key row = wanted then new else row) = key row := by
  split
  · next hit => exact same.trans hit.symm
  · rfl

/-- The keys of the rows stay as they are when a row of one key replaces every row of that key. -/
private theorem map_key_replace [DecidableEq κ] {key : α → κ} {wanted : κ} {new : α}
    (same : key new = wanted) :
    ∀ rows : List α,
      (rows.map fun row => if key row = wanted then new else row).map key = rows.map key
  | [] => rfl
  | row :: rows => by
    show key (if key row = wanted then new else row) :: _ = key row :: rows.map key
    rw [key_replace same row, map_key_replace same rows]

/-- The keys of the rows stay without repetition when a row of one key replaces every row of that key. -/
private theorem nodup_map_key_replace [DecidableEq κ] {key : α → κ} {wanted : κ} {new : α}
    {rows : List α} (same : key new = wanted) (keys : (rows.map key).Nodup) :
    ((rows.map fun row => if key row = wanted then new else row).map key).Nodup := by
  rw [map_key_replace same]
  exact keys

/-- A property of every row and of the new row holds for every row after a replacement. -/
private theorem forall_mem_replace [DecidableEq κ] {P : α → Prop} {key : α → κ} {wanted : κ}
    {new : α} {rows : List α} (old : ∀ row ∈ rows, P row) (added : P new) :
    ∀ row ∈ rows.map (fun row => if key row = wanted then new else row), P row :=
  forall_mem_map.mpr fun row member => by
    show P (if key row = wanted then new else row)
    split
    · exact added
    · exact old row member

/-- A column stays without repetition when a row replaces the row of one key, the keys have no repetition, and no row of another key holds the new row's value of the column. -/
private theorem nodup_map_replace [DecidableEq κ] {key : α → κ} {column : α → β} {wanted : κ}
    {new : α} {rows : List α} (keys : (rows.map key).Nodup) (values : (rows.map column).Nodup)
    (free : ∀ row ∈ rows, key row ≠ wanted → column row ≠ column new) :
    ((rows.map fun row => if key row = wanted then new else row).map column).Nodup :=
  pairwise_map.mpr <| pairwise_map.mpr <|
    (pairwise_and (pairwise_map.mp keys) (pairwise_map.mp values)).imp_of_mem
      fun {row other} member otherMember ⟨keysDiffer, valuesDiffer⟩ => by
        show column (if key row = wanted then new else row) ≠
          column (if key other = wanted then new else other)
        by_cases hit : key row = wanted
        · rw [ite_eq_left hit]
          by_cases otherHit : key other = wanted
          · exact absurd (hit.trans otherHit.symm) keysDiffer
          · rw [ite_eq_right otherHit]
            exact (free other otherMember otherHit).symm
        · rw [ite_eq_right hit]
          by_cases otherHit : key other = wanted
          · rw [ite_eq_left otherHit]
            exact free row member hit
          · rw [ite_eq_right otherHit]
            exact valuesDiffer

/-! ## Searches -/

/-- The test `==` of a decidable equality passes only equal values. -/
private theorem eq_of_beq_true [DecidableEq κ] {a b : κ} (same : (a == b) = true) : a = b :=
  of_decide_eq_true same

/-- The test `==` of a decidable equality passes equal values. -/
private theorem beq_true_of_eq [DecidableEq κ] {a b : κ} (same : a = b) : (a == b) = true :=
  decide_eq_true same

/-- The test `!=` of a decidable equality passes different values. -/
private theorem bne_true_of_ne [DecidableEq κ] {a b : κ} (differs : a ≠ b) : (a != b) = true :=
  congrArg not (decide_eq_false differs)

/-- An option that is not some value is none. -/
private theorem eq_none_of_not_isSome : ∀ {o : Option α}, ¬o.isSome = true → o = none
  | none, _ => rfl
  | some _, notSome => absurd rfl notSome

/-- An option that is not none holds a value. -/
private theorem exists_of_not_isNone : ∀ {o : Option α}, ¬o.isNone = true → ∃ a, o = some a
  | none, notNone => absurd rfl notNone
  | some a, _ => ⟨a, rfl⟩

/-- No element of a list passes a test when the search for one finds nothing. -/
private theorem forall_not_of_find?_eq_none {p : α → Bool} :
    ∀ {l : List α}, l.find? p = none → ∀ a ∈ l, ¬p a = true
  | [], _ => nofun
  | _ :: _, nothing => by
    rw [List.find?_cons] at nothing
    split at nothing
    · cases nothing
    · next fails =>
      exact List.forall_mem_cons.mpr
        ⟨Bool.ne_true_of_eq_false fails, forall_not_of_find?_eq_none nothing⟩

/-- A search returns an element of the list that passes the test. -/
private theorem mem_and_pass_of_find?_eq_some {p : α → Bool} {a : α} :
    ∀ {l : List α}, l.find? p = some a → a ∈ l ∧ p a = true
  | _ :: _, found => by
    rw [List.find?_cons] at found
    split at found
    · next pass =>
      cases found
      exact ⟨.head _, pass⟩
    · have ⟨member, pass⟩ := mem_and_pass_of_find?_eq_some found
      exact ⟨.tail _ member, pass⟩

/-- No row of a list holds a key when the search for the key finds nothing. -/
private theorem forall_key_ne_of_find? [DecidableEq κ] {key : α → κ} {wanted : κ} {rows : List α}
    (absent : ¬(rows.find? fun row => key row == wanted).isSome = true) :
    ∀ row ∈ rows, key row ≠ wanted :=
  fun row member same =>
    forall_not_of_find?_eq_none (eq_none_of_not_isSome absent) row member (beq_true_of_eq same)

/-- A search by key returns a row of the list that holds the key. -/
private theorem key_eq_of_find? [DecidableEq κ] {key : α → κ} {wanted : κ} {rows : List α}
    {found : α} (search : (rows.find? fun row => key row == wanted) = some found) :
    found ∈ rows ∧ key found = wanted :=
  have ⟨member, pass⟩ := mem_and_pass_of_find?_eq_some search
  ⟨member, eq_of_beq_true pass⟩

/-- A row of a list holds a key when the search for the key finds something. -/
private theorem exists_key_eq_of_find? [DecidableEq κ] {key : α → κ} {wanted : κ}
    {rows : List α} (present : ¬(rows.find? fun row => key row == wanted).isNone = true) :
    ∃ row ∈ rows, key row = wanted :=
  have ⟨found, search⟩ := exists_of_not_isNone present
  ⟨found, key_eq_of_find? search⟩

/-- An element that passes a test makes `any` true. -/
private theorem any_of_mem {p : α → Bool} {a : α} :
    ∀ {l : List α}, a ∈ l → p a = true → l.any p = true
  | _ :: _, member, pass => by
    rw [List.any_cons]
    cases member with
    | head => rw [pass, Bool.true_or]
    | tail _ member => rw [any_of_mem member pass, Bool.or_true]

/-- A true `any` has an element that passes the test. -/
private theorem exists_of_any {p : α → Bool} :
    ∀ {l : List α}, l.any p = true → ∃ a ∈ l, p a = true
  | b :: _, passes => by
    rw [List.any_cons] at passes
    cases pass : p b
    · rw [pass, Bool.false_or] at passes
      have ⟨a, member, passA⟩ := exists_of_any passes
      exact ⟨a, .tail _ member, passA⟩
    · exact ⟨b, .head _, pass⟩

/-- An `any` that tests for a key is true exactly when a row of the list holds the key. -/
private theorem any_key_iff [DecidableEq κ] {key : α → κ} {wanted : κ} {rows : List α} :
    (rows.any fun row => key row == wanted) = true ↔ ∃ row ∈ rows, key row = wanted :=
  ⟨fun passes =>
      have ⟨row, member, pass⟩ := exists_of_any passes
      ⟨row, member, eq_of_beq_true pass⟩,
    fun ⟨_, member, same⟩ => any_of_mem member (beq_true_of_eq same)⟩

/-- No row of a list holds a key when the `any` that tests for the key is false. -/
private theorem forall_key_ne_of_any [DecidableEq κ] {key : α → κ} {wanted : κ} {rows : List α}
    (absent : ¬(rows.any fun row => key row == wanted) = true) : ∀ row ∈ rows, key row ≠ wanted :=
  fun row member same => absent (any_key_iff.mpr ⟨row, member, same⟩)

/-- `contains` is true exactly for the elements of a list. -/
private theorem contains_iff_mem [DecidableEq κ] {a : κ} :
    ∀ {l : List κ}, l.contains a = true ↔ a ∈ l
  | [] => ⟨nofun, nofun⟩
  | b :: l => by
    show List.elem a (b :: l) = true ↔ a ∈ b :: l
    rw [List.elem_cons]
    split
    · next same =>
      cases eq_of_beq_true same
      exact ⟨fun _ => .head _, fun _ => rfl⟩
    · next differs =>
      constructor
      · intro contained
        exact .tail _ (contains_iff_mem.mp contained)
      · intro member
        cases member with
        | head => exact absurd (beq_true_of_eq rfl) (Bool.ne_true_of_eq_false differs)
        | tail _ member => exact contains_iff_mem.mpr member

/-! ## Memos -/

/-- A day that is neither before another day nor the same day comes after it. -/
private theorem lt_of_not_lt_of_ne {day other : Day} (notBefore : ¬day < other)
    (differs : ¬day = other) : other < day :=
  ((Int.lt_trichotomy day other).resolve_left notBefore).resolve_left differs

/-- A property of every memo before and of the written memo holds for every memo after `insertMemo`. -/
private theorem forall_mem_insertMemo {P : Day × MemoText → Prop} {day : Day} {text : MemoText} :
    ∀ {memos : List (Day × MemoText)},
      (∀ entry ∈ memos, P entry) → P (day, text) → ∀ entry ∈ insertMemo memos day text, P entry
  | [], _, written => List.forall_mem_cons.mpr ⟨written, nofun⟩
  | (_, _) :: _, before, written => by
    have ⟨head, tail⟩ := List.forall_mem_cons.mp before
    intro entry member
    unfold insertMemo at member
    split at member
    · exact List.forall_mem_cons.mpr ⟨written, before⟩ entry member
    · split at member
      · exact List.forall_mem_cons.mpr ⟨written, tail⟩ entry member
      · exact List.forall_mem_cons.mpr ⟨head, forall_mem_insertMemo tail written⟩ entry member

/-- `insertMemo` keeps the memos in the order of their days. -/
private theorem pairwise_insertMemo {day : Day} {text : MemoText} :
    ∀ {memos : List (Day × MemoText)}, (memos.Pairwise fun earlier later => earlier.1 < later.1) →
      (insertMemo memos day text).Pairwise fun earlier later => earlier.1 < later.1
  | [], _ => List.pairwise_cons.mpr ⟨nofun, .nil⟩
  | (_, _) :: _, ordered => by
    have ⟨head, tail⟩ := List.pairwise_cons.mp ordered
    unfold insertMemo
    split
    · next before =>
      exact List.pairwise_cons.mpr
        ⟨List.forall_mem_cons.mpr
          ⟨before, fun entry member => Int.lt_trans before (head entry member)⟩, ordered⟩
    · split
      · next same =>
        subst same
        exact List.pairwise_cons.mpr ⟨head, tail⟩
      · next notBefore differs =>
        exact List.pairwise_cons.mpr
          ⟨forall_mem_insertMemo head (lt_of_not_lt_of_ne notBefore differs),
            pairwise_insertMemo tail⟩

/-- `writeMemos` keeps the memos in the order of their days. -/
private theorem writeMemos_ordered {memos : List (Day × MemoText)} {day : Day}
    (ordered : (memos.map (·.1)).Pairwise (· < ·)) :
    ∀ memo : Option MemoText, ((writeMemos memos day memo).map (·.1)).Pairwise (· < ·)
  | none => pairwise_map_filter _ ordered
  | some _ => pairwise_map.mpr (pairwise_insertMemo (pairwise_map.mp ordered))

/-! ## What an accepted command did -/

/-- An accepted `addExercise` found no exercise with the identifier or the name, found room, and appended the exercise. -/
private theorem addExercise_accepted {log : Log} {id : ExerciseID} {name : Name}
    {bodyPart : BodyPart} {transition : Transition}
    (accepted : addExercise log id name bodyPart = .accepted transition) :
    (∀ exercise ∈ log.exercises, exercise.id ≠ id) ∧
      (∀ exercise ∈ log.exercises, exercise.name ≠ name) ∧
      log.exercises.length < maximumExercises ∧
      transition =
        ⟨{ log with exercises := log.exercises ++ [⟨id, name, bodyPart, false⟩] },
          [.putExercise ⟨id, name, bodyPart, false⟩]⟩ := by
  unfold addExercise at accepted
  split at accepted
  · cases accepted
  · split at accepted
    · cases accepted
    · split at accepted
      · next unknownID unknownName room =>
        cases accepted
        exact ⟨forall_key_ne_of_find? unknownID, forall_key_ne_of_any unknownName, room, rfl⟩
      · cases accepted

/-- An accepted `replaceExercise` found the exercise, and either left the log alone or put an edit in its place whose name no other exercise holds. -/
private theorem replaceExercise_accepted {log : Log} {id : ExerciseID} {edit : Exercise → Exercise}
    {transition : Transition} (accepted : replaceExercise log id edit = .accepted transition) :
    ∃ current ∈ log.exercises, current.id = id ∧
      (transition = ⟨log, []⟩ ∨
        (∀ other ∈ log.exercises, other.id ≠ id → other.name ≠ (edit current).name) ∧
          transition =
            ⟨{ log with
                exercises :=
                  log.exercises.map fun exercise =>
                    if exercise.id = id then edit current else exercise },
              [.putExercise (edit current)]⟩) := by
  unfold replaceExercise at accepted
  split at accepted
  · cases accepted
  · next current search =>
    have ⟨member, same⟩ := key_eq_of_find? search
    refine ⟨current, member, same, ?_⟩
    dsimp only at accepted
    split at accepted
    · cases accepted
      exact .inl rfl
    · split at accepted
      · cases accepted
      · next free =>
        cases accepted
        refine .inr ⟨fun other stored differs named => free (any_of_mem stored ?_), rfl⟩
        show (other.id != id && other.name == (edit current).name) = true
        rw [bne_true_of_ne differs, beq_true_of_eq named, Bool.and_self]

/-- An accepted `deleteExercise` found no set of the exercise and removed the exercise. -/
private theorem deleteExercise_accepted {log : Log} {id : ExerciseID} {transition : Transition}
    (accepted : deleteExercise log id = .accepted transition) :
    (∀ set ∈ log.sets, set.exerciseID ≠ id) ∧
      transition =
        ⟨{ log with exercises := log.exercises.filter fun exercise => exercise.id != id },
          [.removeExercise id]⟩ := by
  unfold deleteExercise at accepted
  split at accepted
  · cases accepted
  · split at accepted
    · cases accepted
    · next unused =>
      cases accepted
      exact ⟨forall_key_ne_of_any unused, rfl⟩

/-- An accepted `logSet` found the exercise of the set, found no set with the identifier, found room, and appended the set. -/
private theorem logSet_accepted {log : Log} {set : LoggedSet} {transition : Transition}
    (accepted : logSet log set = .accepted transition) :
    (∃ exercise ∈ log.exercises, exercise.id = set.exerciseID) ∧
      (∀ other ∈ log.sets, other.id ≠ set.id) ∧
      log.sets.length < maximumSets ∧
      transition = ⟨{ log with sets := log.sets ++ [set] }, [.putSet set]⟩ := by
  unfold logSet at accepted
  split at accepted
  · cases accepted
  · split at accepted
    · cases accepted
    · split at accepted
      · next knownExercise unknownID room =>
        cases accepted
        exact ⟨exists_key_eq_of_find? knownExercise, forall_key_ne_of_find? unknownID, room, rfl⟩
      · cases accepted

/-- An accepted `editSet` found the set, and either left the log alone or put the set with the new weight and repetitions in its place. -/
private theorem editSet_accepted {log : Log} {id : SetID} {weight reps : Nat}
    {transition : Transition} (accepted : editSet log id weight reps = .accepted transition) :
    ∃ current ∈ log.sets, current.id = id ∧
      (transition = ⟨log, []⟩ ∨
        transition =
          ⟨{ log with
              sets :=
                log.sets.map fun set =>
                  if set.id = id then { current with weight := weight, reps := reps } else set },
            [.putSet { current with weight := weight, reps := reps }]⟩) := by
  unfold editSet at accepted
  split at accepted
  · cases accepted
  · next current search =>
    have ⟨member, same⟩ := key_eq_of_find? search
    refine ⟨current, member, same, ?_⟩
    dsimp only at accepted
    split at accepted
    · cases accepted
      exact .inl rfl
    · cases accepted
      exact .inr rfl

/-- An accepted `deleteSet` removed the set. -/
private theorem deleteSet_accepted {log : Log} {id : SetID} {transition : Transition}
    (accepted : deleteSet log id = .accepted transition) :
    transition =
      ⟨{ log with sets := log.sets.filter fun set => set.id != id }, [.removeSet id]⟩ := by
  unfold deleteSet at accepted
  split at accepted
  · cases accepted
  · cases accepted
    rfl

/-- An accepted `writeMemo` either left the log alone or wrote the memos with one change. -/
private theorem writeMemo_accepted {log : Log} {day : Day} {memo : Option MemoText}
    {transition : Transition} (accepted : writeMemo log day memo = .accepted transition) :
    transition = ⟨log, []⟩ ∨
      ∃ change, transition = ⟨{ log with memos := writeMemos log.memos day memo }, [change]⟩ := by
  unfold writeMemo at accepted
  split at accepted
  · cases accepted
    exact .inl rfl
  · cases accepted
    exact .inr ⟨_, rfl⟩

/-! ## The invariants after each command -/

/-- An accepted `addExercise` keeps the invariants. -/
private theorem addExercise_valid {log : Log} {id : ExerciseID} {name : Name} {bodyPart : BodyPart}
    {transition : Transition} (valid : Valid log)
    (accepted : addExercise log id name bodyPart = .accepted transition) :
    Valid transition.log := by
  obtain ⟨unknownID, unknownName, room, rfl⟩ := addExercise_accepted accepted
  exact { valid with
    exerciseIDs := nodup_map_append_singleton valid.exerciseIDs unknownID
    exerciseNames := nodup_map_append_singleton valid.exerciseNames unknownName
    setsNameExercises := fun set member =>
      have ⟨exercise, stored, named⟩ := valid.setsNameExercises set member
      ⟨exercise, List.mem_append_left _ stored, named⟩
    exerciseCount :=
      Nat.le_trans (Nat.le_of_eq (length_append_singleton _ _)) (Nat.succ_le_of_lt room) }

/-- An accepted `replaceExercise` keeps the invariants when the edit keeps the identifier. -/
private theorem replaceExercise_valid {log : Log} {id : ExerciseID} {edit : Exercise → Exercise}
    {transition : Transition} (valid : Valid log)
    (accepted : replaceExercise log id edit = .accepted transition)
    (keepsID : ∀ exercise, (edit exercise).id = exercise.id) : Valid transition.log := by
  obtain ⟨current, _, found, rfl | ⟨free, rfl⟩⟩ := replaceExercise_accepted accepted
  · exact valid
  · have same : (edit current).id = id := (keepsID current).trans found
    exact { valid with
      exerciseIDs := nodup_map_key_replace same valid.exerciseIDs
      exerciseNames := nodup_map_replace valid.exerciseIDs valid.exerciseNames free
      setsNameExercises := fun set member =>
        have ⟨exercise, stored, named⟩ := valid.setsNameExercises set member
        ⟨_, mem_map_of_mem stored, (key_replace same exercise).trans named⟩
      exerciseCount := Nat.le_trans (Nat.le_of_eq (length_map _ _)) valid.exerciseCount }

/-- An accepted `deleteExercise` keeps the invariants. -/
private theorem deleteExercise_valid {log : Log} {id : ExerciseID} {transition : Transition}
    (valid : Valid log) (accepted : deleteExercise log id = .accepted transition) :
    Valid transition.log := by
  obtain ⟨unused, rfl⟩ := deleteExercise_accepted accepted
  exact { valid with
    exerciseIDs := pairwise_map_filter _ valid.exerciseIDs
    exerciseNames := pairwise_map_filter _ valid.exerciseNames
    setsNameExercises := fun set member =>
      have ⟨exercise, stored, named⟩ := valid.setsNameExercises set member
      have kept : exercise.id ≠ id := fun deleted => unused set member (named.symm.trans deleted)
      ⟨exercise, mem_filter_of_mem stored (bne_true_of_ne kept), named⟩
    exerciseCount := Nat.le_trans (filter_sublist _ _).length_le valid.exerciseCount }

/-- An accepted `logSet` keeps the invariants. -/
private theorem logSet_valid {log : Log} {set : LoggedSet} {transition : Transition}
    (valid : Valid log) (accepted : logSet log set = .accepted transition) :
    Valid transition.log := by
  obtain ⟨knownExercise, unknownID, room, rfl⟩ := logSet_accepted accepted
  exact { valid with
    setIDs := nodup_map_append_singleton valid.setIDs unknownID
    setsNameExercises := forall_mem_append_singleton valid.setsNameExercises knownExercise
    setCount :=
      Nat.le_trans (Nat.le_of_eq (length_append_singleton _ _)) (Nat.succ_le_of_lt room) }

/-- An accepted `editSet` keeps the invariants. -/
private theorem editSet_valid {log : Log} {id : SetID} {weight reps : Nat}
    {transition : Transition} (valid : Valid log)
    (accepted : editSet log id weight reps = .accepted transition) : Valid transition.log := by
  obtain ⟨current, member, same, rfl | rfl⟩ := editSet_accepted accepted
  · exact valid
  · exact { valid with
      setIDs := nodup_map_key_replace same valid.setIDs
      setsNameExercises :=
        forall_mem_replace valid.setsNameExercises (valid.setsNameExercises current member)
      setCount := Nat.le_trans (Nat.le_of_eq (length_map _ _)) valid.setCount }

/-- An accepted `deleteSet` keeps the invariants. -/
private theorem deleteSet_valid {log : Log} {id : SetID} {transition : Transition}
    (valid : Valid log) (accepted : deleteSet log id = .accepted transition) :
    Valid transition.log := by
  obtain rfl := deleteSet_accepted accepted
  exact { valid with
    setIDs := pairwise_map_filter _ valid.setIDs
    setsNameExercises := fun set member =>
      valid.setsNameExercises set ((filter_sublist _ _).subset member)
    setCount := Nat.le_trans (filter_sublist _ _).length_le valid.setCount }

/-- An accepted `writeMemo` keeps the invariants. -/
private theorem writeMemo_valid {log : Log} {day : Day} {memo : Option MemoText}
    {transition : Transition} (valid : Valid log)
    (accepted : writeMemo log day memo = .accepted transition) : Valid transition.log := by
  obtain rfl | ⟨_, rfl⟩ := writeMemo_accepted accepted
  · exact valid
  · exact { valid with memoDays := writeMemos_ordered valid.memoDays memo }

/-! ## The rows that `make` accepts -/

/-- The elements of `new` differ from each other and from the elements of `seen`. -/
private def Fresh (new seen : List α) : Prop :=
  new.Nodup ∧ ∀ a ∈ new, a ∉ seen

/-- The empty list is fresh after any elements. -/
private theorem nil_fresh {seen : List α} : Fresh [] seen :=
  ⟨.nil, nofun⟩

/-- A list is fresh after the elements read before exactly when its head is not among them and its tail is fresh after the head and them. -/
private theorem fresh_cons {a : α} {new seen : List α} :
    Fresh (a :: new) seen ↔ a ∉ seen ∧ Fresh new (a :: seen) := by
  constructor
  · intro ⟨nodup, unseen⟩
    have ⟨differs, rest⟩ := List.pairwise_cons.mp nodup
    have ⟨head, tail⟩ := List.forall_mem_cons.mp unseen
    refine ⟨head, rest, fun b member seenB => ?_⟩
    cases seenB with
    | head => exact differs _ member rfl
    | tail _ seenB => exact tail b member seenB
  · intro ⟨head, rest, unseen⟩
    refine ⟨List.pairwise_cons.mpr ⟨fun b member same => ?_, rest⟩,
      List.forall_mem_cons.mpr ⟨head, fun b member seenB => unseen b member (.tail _ seenB)⟩⟩
    subst same
    exact unseen _ member (.head _)

/-- A list is fresh after nothing exactly when it has no repetition. -/
private theorem fresh_nil_iff_nodup {new : List α} : Fresh new [] ↔ new.Nodup :=
  ⟨fun fresh => fresh.1, fun nodup => ⟨nodup, fun _ _ => nofun⟩⟩

/-- `checkExercises` finds nothing exactly when the identifiers and the names of the exercises are fresh after those read before. -/
private theorem checkExercises_eq_none :
    ∀ {exercises : List Exercise} {ids : List ExerciseID} {names : List Name},
      checkExercises exercises ids names = none ↔
        Fresh (exercises.map (·.id)) ids ∧ Fresh (exercises.map (·.name)) names
  | [], _, _ => ⟨fun _ => ⟨nil_fresh, nil_fresh⟩, fun _ => rfl⟩
  | _ :: _, _, _ => by
    constructor
    · intro nothing
      unfold checkExercises at nothing
      split at nothing
      · cases nothing
      · split at nothing
        · cases nothing
        · next newID newName =>
          have ⟨restIDs, restNames⟩ := checkExercises_eq_none.mp nothing
          exact ⟨fresh_cons.mpr ⟨mt contains_iff_mem.mpr newID, restIDs⟩,
            fresh_cons.mpr ⟨mt contains_iff_mem.mpr newName, restNames⟩⟩
    · intro ⟨freshIDs, freshNames⟩
      have ⟨newID, restIDs⟩ := fresh_cons.mp freshIDs
      have ⟨newName, restNames⟩ := fresh_cons.mp freshNames
      unfold checkExercises
      rw [ite_eq_right (mt contains_iff_mem.mp newID),
        ite_eq_right (mt contains_iff_mem.mp newName)]
      exact checkExercises_eq_none.mpr ⟨restIDs, restNames⟩

/-- `checkSets` finds nothing exactly when the identifiers of the sets are fresh after those read before and every set names a stored exercise. -/
private theorem checkSets_eq_none {exercises : List Exercise} :
    ∀ {sets : List LoggedSet} {ids : List SetID},
      checkSets exercises sets ids = none ↔
        Fresh (sets.map (·.id)) ids ∧
          ∀ set ∈ sets, ∃ exercise ∈ exercises, exercise.id = set.exerciseID
  | [], _ => ⟨fun _ => ⟨nil_fresh, nofun⟩, fun _ => rfl⟩
  | _ :: _, _ => by
    constructor
    · intro nothing
      unfold checkSets at nothing
      split at nothing
      · cases nothing
      · split at nothing
        · next newID named =>
          have ⟨restIDs, restNamed⟩ := checkSets_eq_none.mp nothing
          exact ⟨fresh_cons.mpr ⟨mt contains_iff_mem.mpr newID, restIDs⟩,
            List.forall_mem_cons.mpr ⟨any_key_iff.mp named, restNamed⟩⟩
        · cases nothing
    · intro ⟨freshIDs, named⟩
      have ⟨newID, restIDs⟩ := fresh_cons.mp freshIDs
      have ⟨firstNamed, restNamed⟩ := List.forall_mem_cons.mp named
      unfold checkSets
      rw [ite_eq_right (mt contains_iff_mem.mp newID), ite_eq_left (any_key_iff.mpr firstNamed)]
      exact checkSets_eq_none.mpr ⟨restIDs, restNamed⟩

/-! ## The theorems -/

/-- The empty log holds the invariants. -/
theorem empty_valid : Valid Log.empty where
  exerciseIDs := .nil
  exerciseNames := .nil
  setIDs := .nil
  setsNameExercises := nofun
  exerciseCount := Nat.zero_le _
  setCount := Nat.zero_le _
  memoDays := .nil

/-- Every accepted command keeps the invariants. -/
theorem apply_valid {log : Log} {command : Command} {transition : Transition} (valid : Valid log)
    (admissible : Admissible command) (accepted : apply log command = .accepted transition) :
    Valid transition.log := by
  cases command with
  | addExercise _ name _ =>
    cases name with
    | refused _ => cases accepted
    | accepted _ => exact addExercise_valid valid accepted
  | editExercise _ name _ =>
    cases name with
    | refused _ => cases accepted
    | accepted _ => exact replaceExercise_valid valid accepted fun _ => rfl
  | setExerciseArchived _ _ => exact replaceExercise_valid valid accepted fun _ => rfl
  | deleteExercise _ => exact deleteExercise_valid valid accepted
  | logSet _ _ _ _ _ => exact logSet_valid valid accepted
  | editSet _ _ _ => exact editSet_valid valid accepted
  | deleteSet _ => exact deleteSet_valid valid accepted
  | writeMemo _ memo =>
    cases memo with
    | refused _ => cases accepted
    | nothing | kept _ => exact writeMemo_valid valid accepted
  | replaceAll _ =>
    cases accepted
    exact admissible

/-- Every sequence of commands keeps the invariants. -/
theorem applied_valid {log : Log} {commands : List Command} (valid : Valid log)
    (admissible : ∀ command ∈ commands, Admissible command) : Valid (applied log commands) := by
  induction commands generalizing log with
  | nil => exact valid
  | cons _ _ keeps =>
    have ⟨first, later⟩ := List.forall_mem_cons.mp admissible
    unfold applied
    split
    · exact keeps valid later
    · next accepted => exact keeps (apply_valid valid first accepted) later

/-- `TrainingLog.make` accepts exactly the rows that form a log.
The order of the memos is a hypothesis, because the Swift code takes a dictionary, which has no repeated day. -/
theorem make_none_iff_valid {rows : Log} (ordered : (rows.memos.map (·.1)).Pairwise (· < ·)) :
    make rows = none ↔ Valid rows := by
  constructor
  · intro nothing
    unfold make at nothing
    split at nothing
    · cases nothing
    · split at nothing
      · cases nothing
      · split at nothing
        · cases nothing
        · next fewExercises fewSets _ checked =>
          have ⟨ids, names⟩ := checkExercises_eq_none.mp checked
          have ⟨setIDs, named⟩ := checkSets_eq_none.mp nothing
          exact
            { exerciseIDs := fresh_nil_iff_nodup.mp ids
              exerciseNames := fresh_nil_iff_nodup.mp names
              setIDs := fresh_nil_iff_nodup.mp setIDs
              setsNameExercises := named
              exerciseCount := Nat.le_of_not_lt fewExercises
              setCount := Nat.le_of_not_lt fewSets
              memoDays := ordered }
  · intro valid
    unfold make
    rw [ite_eq_right (Nat.not_lt_of_le valid.exerciseCount),
      ite_eq_right (Nat.not_lt_of_le valid.setCount),
      checkExercises_eq_none.mpr
        ⟨fresh_nil_iff_nodup.mpr valid.exerciseIDs, fresh_nil_iff_nodup.mpr valid.exerciseNames⟩]
    exact checkSets_eq_none.mpr ⟨fresh_nil_iff_nodup.mpr valid.setIDs, valid.setsNameExercises⟩

/-- A transition without changes returns the same log. -/
theorem unchanged_log {log : Log} {command : Command} {transition : Transition}
    (accepted : apply log command = .accepted transition) (none : transition.changes = []) :
    transition.log = log := by
  cases command with
  | addExercise _ name _ =>
    cases name with
    | refused _ => cases accepted
    | accepted _ =>
      obtain ⟨_, _, _, rfl⟩ := addExercise_accepted accepted
      cases none
  | editExercise _ name _ =>
    cases name with
    | refused _ => cases accepted
    | accepted _ =>
      obtain ⟨_, _, _, rfl | ⟨_, rfl⟩⟩ := replaceExercise_accepted accepted
      · rfl
      · cases none
  | setExerciseArchived _ _ =>
    obtain ⟨_, _, _, rfl | ⟨_, rfl⟩⟩ := replaceExercise_accepted accepted
    · rfl
    · cases none
  | deleteExercise _ =>
    obtain ⟨_, rfl⟩ := deleteExercise_accepted accepted
    cases none
  | logSet _ _ _ _ _ =>
    obtain ⟨_, _, _, rfl⟩ := logSet_accepted accepted
    cases none
  | editSet _ _ _ =>
    obtain ⟨_, _, _, rfl | rfl⟩ := editSet_accepted accepted
    · rfl
    · cases none
  | deleteSet _ =>
    obtain rfl := deleteSet_accepted accepted
    cases none
  | writeMemo _ memo =>
    cases memo with
    | refused _ => cases accepted
    | nothing | kept _ =>
      obtain rfl | ⟨_, rfl⟩ := writeMemo_accepted accepted
      · rfl
      · cases none
  | replaceAll _ =>
    cases accepted
    cases none

end Gymemo.Log
