import Gymemo.LogStore
import Gymemo.LogValid
import Gymemo.PositionsProofs

/-!
# The rules of the log over a sequence of commands

`Gymemo/LogValid.lean` and `Gymemo/LogStore.lean` speak of one command.
The vectors in `Gymemo/LogVectors.lean` record what `outcomes` gives for a sequence of commands.
This file ties the two together: over any sequence, the log holds its invariants, the recorded changes rebuild it, and the positional statement of the Swift code gives the same record.
-/

namespace Gymemo.Log

/-- The changes of the accepted steps, in order. -/
def recorded : List Step → List Change
  | [] => []
  | .refused _ :: later => recorded later
  | .changed changes :: later => changes ++ recorded later

/-- A positional rule that accepts a command on a log that holds the invariants returns a log that holds them. -/
theorem positions_apply_valid {log : Log} {command : Command} {transition : Transition}
    (valid : Valid log) (admissible : Admissible command)
    (accepted : Positions.apply log command = .accepted transition) : Valid transition.log :=
  apply_valid valid admissible (positions_apply_eq valid ▸ accepted)

/-- Over any sequence of commands, the store that received every change holds the rows of the log. -/
theorem stored_applied {log : Log} {commands : List Command} (valid : Valid log)
    (admissible : ∀ command ∈ commands, Admissible command) :
    stored log log commands = applied log commands :=
  stored_eq_applied valid admissible apply_valid

/-- The log that `outcomes` records after a sequence is the log after each accepted command. -/
theorem outcomes_applied (log : Log) (commands : List Command) :
    (outcomes log commands).2 = applied log commands := by
  induction commands generalizing log with
  | nil => rfl
  | cons command rest step =>
    unfold outcomes applied
    cases apply log command with
    | refused refusal => exact step log
    | accepted transition => exact step transition.log

/-- The store of a sequence applies exactly the changes that `outcomes` records. -/
private theorem stored_recorded (log rows : Log) (commands : List Command) :
    stored log rows commands = storeAll rows (recorded (outcomes log commands).1) := by
  induction commands generalizing log rows with
  | nil => rfl
  | cons command rest step =>
    unfold stored outcomes
    cases apply log command with
    | refused refusal => exact step log rows
    | accepted transition =>
      show stored transition.log (storeAll rows transition.changes) rest
        = storeAll rows (transition.changes ++ recorded (outcomes transition.log rest).1)
      rw [step transition.log (storeAll rows transition.changes)]
      unfold storeAll
      rw [List.foldl_append]

/-- Over any sequence of commands, the changes that `outcomes` records rebuild the log that it records.
A vector states `outcomes` for one sequence, so this theorem holds for each vector's steps and final log. -/
theorem recorded_rebuild {log : Log} {commands : List Command} (valid : Valid log)
    (admissible : ∀ command ∈ commands, Admissible command) :
    storeAll log (recorded (outcomes log commands).1) = (outcomes log commands).2 := by
  rw [← stored_recorded, stored_applied valid admissible, outcomes_applied]

/-- Over any sequence of commands from a log that holds the invariants, the positional statement of the Swift code records what the model records. -/
theorem positions_outcomes_eq {log : Log} {commands : List Command} (valid : Valid log)
    (admissible : ∀ command ∈ commands, Admissible command) :
    Positions.outcomes log commands = outcomes log commands := by
  induction commands generalizing log with
  | nil => rfl
  | cons command rest step =>
    have fits : Admissible command := admissible command (List.Mem.head _)
    have later : ∀ next ∈ rest, Admissible next :=
      fun next member => admissible next (List.Mem.tail _ member)
    unfold Positions.outcomes outcomes
    rw [positions_apply_eq valid]
    cases accepted : apply log command with
    | refused refusal =>
      dsimp only
      rw [step valid later]
    | accepted transition =>
      dsimp only
      rw [step (apply_valid valid fits accepted) later]

end Gymemo.Log
