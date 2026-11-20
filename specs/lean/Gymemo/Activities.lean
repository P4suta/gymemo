/-! Timed activity changes and their stored rows. -/

namespace Gymemo.Activities

structure Activity where
  id : Nat
  name : Nat
  tracksDistance : Bool
deriving DecidableEq, Repr

structure Record where
  id : Nat
  activity : Nat
  day : Int
  minutes : Nat
  meters : Option Nat
deriving DecidableEq, Repr

structure Log where
  activities : List Activity
  records : List Record
deriving DecidableEq, Repr

def empty : Log := ⟨[], []⟩
def walking : Nat := 1

inductive Command
  | add (activity : Activity)
  | record (entry : Record)
  | edit (id minutes : Nat) (meters : Option Nat)
  | delete (id : Nat)
deriving DecidableEq, Repr

inductive Change
  | putActivity (activity : Activity)
  | putRecord (entry : Record)
  | removeRecord (id : Nat)
deriving DecidableEq, Repr

structure Transition where
  log : Log
  changes : List Change
deriving DecidableEq, Repr

def validRecord (log : Log) (record : Record) : Bool :=
  let definition := log.activities.find? (fun activity => activity.id == record.activity)
  let allowsMeters := record.activity == walking || (definition.map (·.tracksDistance)).getD false
  let metersValid := record.meters.all (fun meters => 0 < meters && meters ≤ 1000000)
  (record.activity == walking || definition.isSome) &&
    (record.meters.isNone || allowsMeters) &&
    (0 < record.minutes && record.minutes ≤ 1440) && metersValid

def valid (log : Log) : Bool :=
  decide ((log.activities.map (·.id)).Nodup ∧ (log.activities.map (·.name)).Nodup ∧
    (log.records.map (·.id)).Nodup ∧ log.activities.length ≤ 1000 ∧
    log.records.length ≤ 1000000) &&
    log.activities.all (fun activity => activity.id != walking) &&
    log.records.all (validRecord log)

def proposed (log : Log) : Command → Option (List Change)
  | .add activity => some [.putActivity activity]
  | .record entry =>
    if log.records.any (fun record => record.id == entry.id) then none
    else some [.putRecord entry]
  | .edit id minutes meters => do
    let record ← log.records.find? (fun record => record.id == id)
    let revised := { record with minutes := minutes, meters := meters }
    pure (if record = revised then [] else [.putRecord revised])
  | .delete id =>
    if log.records.any (fun record => record.id == id) then some [.removeRecord id]
    else none

def store (log : Log) : Change → Log
  | .putActivity activity => { log with activities := log.activities ++ [activity] }
  | .putRecord entry =>
    let records :=
      if log.records.any (fun record => record.id == entry.id) then
        log.records.map (fun record => if record.id == entry.id then entry else record)
      else log.records ++ [entry]
    { log with records := records }
  | .removeRecord id => { log with records := log.records.filter (fun record => record.id != id) }

def apply (log : Log) (command : Command) : Option Transition :=
  match proposed log command with
  | none => none
  | some changes =>
    let next := changes.foldl store log
    if valid next then some ⟨next, changes⟩ else none

theorem acceptedLogIsValid (h : apply log command = some transition) :
    valid transition.log = true := by
  unfold apply at h
  split at h
  · simp at h
  · dsimp only at h
    split at h
    · rename_i accepted
      cases h
      exact accepted
    · simp at h

theorem changesRebuildTheLog (h : apply log command = some transition) :
    transition.changes.foldl store log = transition.log := by
  unfold apply at h
  split at h
  · simp at h
  · dsimp only at h
    split at h
    · cases h
      rfl
    · simp at h

def run (log : Log) : List Command → List (Option (List Change)) × Log
  | [] => ([], log)
  | command :: rest =>
    match apply log command with
    | none =>
      let (steps, final) := run log rest
      (none :: steps, final)
    | some transition =>
      let (steps, final) := run transition.log rest
      (some transition.changes :: steps, final)

end Gymemo.Activities
