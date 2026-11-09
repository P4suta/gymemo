import Gymemo
import Lean

/-!
# The axioms under the theorems

This file prints every theorem of the `Gymemo` modules with the axioms that it rests on.
The first line counts the theorems, and each further line names one theorem and its axioms.
`just proofs` reads the lines and refuses an axiom beyond `propext`, `Classical.choice`, and `Quot.sound`.
It also refuses the run when a theorem of the sources has no line here.
-/

open Lean Elab Command

run_cmd do
  let env ← getEnv
  let theorems := env.constants.fold (init := #[]) fun found name info =>
    match info, env.getModuleIdxFor? name with
    | .thmInfo _, some index =>
      if (`Gymemo).isPrefixOf env.header.moduleNames[index]! then found.push name else found
    | _, _ => found
  let ordered := theorems.qsort fun first second => first.toString < second.toString
  IO.println s!"theorems {ordered.size}"
  for name in ordered do
    let axioms ← liftCoreM (collectAxioms name)
    let sorted := axioms.qsort fun first second => first.toString < second.toString
    IO.println s!"theorem {name} axioms {" ".intercalate (sorted.toList.map toString)}"
