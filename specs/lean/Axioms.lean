import Gymemo
import Lean

/-!
# The axioms under the theorems

This file prints every proposition that the `Gymemo` modules prove, with the axioms that its proof rests on.
A proposition here is a theorem or any other declaration whose type is a proposition, such as a `def`, an `opaque`, or an `instance`.
The first line counts the propositions, and each further line names one proposition and its axioms.
After them, one line names each axiom that the modules declare.
`just proofs` reads the lines and refuses a declared axiom and an axiom beyond `propext`, `Classical.choice`, and `Quot.sound`.
It also refuses the run when a theorem of the sources has no line here.
-/

open Lean Elab Command

run_cmd do
  let env ← getEnv
  let declared := env.constants.fold (init := #[]) fun found name info =>
    match env.getModuleIdxFor? name with
    | some index =>
      if (`Gymemo).isPrefixOf env.header.moduleNames[index]! then found.push (name, info) else found
    | none => found
  let ordered := declared.qsort fun first second => first.1.toString < second.1.toString
  let propositions ← liftTermElabM <| ordered.filterM fun (_, info) =>
    match info with
    | .axiomInfo _ => pure false
    | .thmInfo _ => pure true
    | _ => Meta.isProp info.type
  IO.println s!"theorems {propositions.size}"
  for (name, _) in propositions do
    let axioms ← liftCoreM (collectAxioms name)
    let sorted := axioms.qsort fun first second => first.toString < second.toString
    IO.println s!"theorem {name} axioms {" ".intercalate (sorted.toList.map toString)}"
  for (name, info) in ordered do
    if info matches .axiomInfo _ then
      IO.println s!"axiom {name}"
