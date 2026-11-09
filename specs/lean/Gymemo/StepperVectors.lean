import Gymemo.Stepper

/-!
# Results of the Swift code for the steppers

`Tests/GymemoCoreTests/LeanVectors.swift` writes this file from what `Weight.stepped` and `Reps.stepped` return for the text of a field, and `mise x -- just gen` runs it.
A package test fails while this file differs from those results, so no change by hand lasts.
After `mise x -- just gen`, `lake build --wfail` in `specs/lean` checks the theorems.
Each line holds when `weightStepped` or `repsStepped` of `Gymemo/Stepper.lean` gives the result of the Swift code from the same start by the same step count.
An empty weight field starts at zero.
An empty repetitions field starts at zero when it steps up, and the Swift code gives no count when it steps down or stays, so no line holds such a pair.
The first and the last step count of each theorem are the least and the greatest 64-bit integer.
-/

namespace Gymemo.Stepper.Vectors

/-- The limits and the weight step of the Swift code. -/
theorem constants :
    maximumHundredths = 99999 ∧
    stepHundredths = 250 ∧
    maximumCount = 999 := by
  decide +kernel

/-- The weight field is empty. -/
theorem weightStepped_fromEmpty :
    weightStepped 0 (-9223372036854775808) = 0 ∧
    weightStepped 0 (-100000) = 0 ∧
    weightStepped 0 (-1000) = 0 ∧
    weightStepped 0 (-999) = 0 ∧
    weightStepped 0 (-998) = 0 ∧
    weightStepped 0 (-400) = 0 ∧
    weightStepped 0 (-399) = 0 ∧
    weightStepped 0 (-1) = 0 ∧
    weightStepped 0 0 = 0 ∧
    weightStepped 0 1 = 250 ∧
    weightStepped 0 399 = 99750 ∧
    weightStepped 0 400 = 99999 ∧
    weightStepped 0 998 = 99999 ∧
    weightStepped 0 999 = 99999 ∧
    weightStepped 0 1000 = 99999 ∧
    weightStepped 0 100000 = 99999 ∧
    weightStepped 0 9223372036854775807 = 99999 := by
  decide +kernel

/-- The weight field holds `0`. -/
theorem weightStepped_from0 :
    weightStepped 0 (-9223372036854775808) = 0 ∧
    weightStepped 0 (-100000) = 0 ∧
    weightStepped 0 (-1000) = 0 ∧
    weightStepped 0 (-999) = 0 ∧
    weightStepped 0 (-998) = 0 ∧
    weightStepped 0 (-400) = 0 ∧
    weightStepped 0 (-399) = 0 ∧
    weightStepped 0 (-1) = 0 ∧
    weightStepped 0 0 = 0 ∧
    weightStepped 0 1 = 250 ∧
    weightStepped 0 399 = 99750 ∧
    weightStepped 0 400 = 99999 ∧
    weightStepped 0 998 = 99999 ∧
    weightStepped 0 999 = 99999 ∧
    weightStepped 0 1000 = 99999 ∧
    weightStepped 0 100000 = 99999 ∧
    weightStepped 0 9223372036854775807 = 99999 := by
  decide +kernel

/-- The weight field holds `0.01`. -/
theorem weightStepped_from1 :
    weightStepped 1 (-9223372036854775808) = 0 ∧
    weightStepped 1 (-100000) = 0 ∧
    weightStepped 1 (-1000) = 0 ∧
    weightStepped 1 (-999) = 0 ∧
    weightStepped 1 (-998) = 0 ∧
    weightStepped 1 (-400) = 0 ∧
    weightStepped 1 (-399) = 0 ∧
    weightStepped 1 (-1) = 0 ∧
    weightStepped 1 0 = 1 ∧
    weightStepped 1 1 = 251 ∧
    weightStepped 1 399 = 99751 ∧
    weightStepped 1 400 = 99999 ∧
    weightStepped 1 998 = 99999 ∧
    weightStepped 1 999 = 99999 ∧
    weightStepped 1 1000 = 99999 ∧
    weightStepped 1 100000 = 99999 ∧
    weightStepped 1 9223372036854775807 = 99999 := by
  decide +kernel

/-- The weight field holds `2.5`. -/
theorem weightStepped_from250 :
    weightStepped 250 (-9223372036854775808) = 0 ∧
    weightStepped 250 (-100000) = 0 ∧
    weightStepped 250 (-1000) = 0 ∧
    weightStepped 250 (-999) = 0 ∧
    weightStepped 250 (-998) = 0 ∧
    weightStepped 250 (-400) = 0 ∧
    weightStepped 250 (-399) = 0 ∧
    weightStepped 250 (-1) = 0 ∧
    weightStepped 250 0 = 250 ∧
    weightStepped 250 1 = 500 ∧
    weightStepped 250 399 = 99999 ∧
    weightStepped 250 400 = 99999 ∧
    weightStepped 250 998 = 99999 ∧
    weightStepped 250 999 = 99999 ∧
    weightStepped 250 1000 = 99999 ∧
    weightStepped 250 100000 = 99999 ∧
    weightStepped 250 9223372036854775807 = 99999 := by
  decide +kernel

/-- The weight field holds `60`. -/
theorem weightStepped_from6000 :
    weightStepped 6000 (-9223372036854775808) = 0 ∧
    weightStepped 6000 (-100000) = 0 ∧
    weightStepped 6000 (-1000) = 0 ∧
    weightStepped 6000 (-999) = 0 ∧
    weightStepped 6000 (-998) = 0 ∧
    weightStepped 6000 (-400) = 0 ∧
    weightStepped 6000 (-399) = 0 ∧
    weightStepped 6000 (-1) = 5750 ∧
    weightStepped 6000 0 = 6000 ∧
    weightStepped 6000 1 = 6250 ∧
    weightStepped 6000 399 = 99999 ∧
    weightStepped 6000 400 = 99999 ∧
    weightStepped 6000 998 = 99999 ∧
    weightStepped 6000 999 = 99999 ∧
    weightStepped 6000 1000 = 99999 ∧
    weightStepped 6000 100000 = 99999 ∧
    weightStepped 6000 9223372036854775807 = 99999 := by
  decide +kernel

/-- The weight field holds `62.5`. -/
theorem weightStepped_from6250 :
    weightStepped 6250 (-9223372036854775808) = 0 ∧
    weightStepped 6250 (-100000) = 0 ∧
    weightStepped 6250 (-1000) = 0 ∧
    weightStepped 6250 (-999) = 0 ∧
    weightStepped 6250 (-998) = 0 ∧
    weightStepped 6250 (-400) = 0 ∧
    weightStepped 6250 (-399) = 0 ∧
    weightStepped 6250 (-1) = 6000 ∧
    weightStepped 6250 0 = 6250 ∧
    weightStepped 6250 1 = 6500 ∧
    weightStepped 6250 399 = 99999 ∧
    weightStepped 6250 400 = 99999 ∧
    weightStepped 6250 998 = 99999 ∧
    weightStepped 6250 999 = 99999 ∧
    weightStepped 6250 1000 = 99999 ∧
    weightStepped 6250 100000 = 99999 ∧
    weightStepped 6250 9223372036854775807 = 99999 := by
  decide +kernel

/-- The weight field holds `999.99`. -/
theorem weightStepped_from99999 :
    weightStepped 99999 (-9223372036854775808) = 0 ∧
    weightStepped 99999 (-100000) = 0 ∧
    weightStepped 99999 (-1000) = 0 ∧
    weightStepped 99999 (-999) = 0 ∧
    weightStepped 99999 (-998) = 0 ∧
    weightStepped 99999 (-400) = 0 ∧
    weightStepped 99999 (-399) = 249 ∧
    weightStepped 99999 (-1) = 99749 ∧
    weightStepped 99999 0 = 99999 ∧
    weightStepped 99999 1 = 99999 ∧
    weightStepped 99999 399 = 99999 ∧
    weightStepped 99999 400 = 99999 ∧
    weightStepped 99999 998 = 99999 ∧
    weightStepped 99999 999 = 99999 ∧
    weightStepped 99999 1000 = 99999 ∧
    weightStepped 99999 100000 = 99999 ∧
    weightStepped 99999 9223372036854775807 = 99999 := by
  decide +kernel

/-- The repetitions field is empty. -/
theorem repsStepped_fromEmpty :
    repsStepped 0 1 = 1 ∧
    repsStepped 0 399 = 399 ∧
    repsStepped 0 400 = 400 ∧
    repsStepped 0 998 = 998 ∧
    repsStepped 0 999 = 999 ∧
    repsStepped 0 1000 = 999 ∧
    repsStepped 0 100000 = 999 ∧
    repsStepped 0 9223372036854775807 = 999 := by
  decide +kernel

/-- The repetitions field holds `1`. -/
theorem repsStepped_from1 :
    repsStepped 1 (-9223372036854775808) = 1 ∧
    repsStepped 1 (-100000) = 1 ∧
    repsStepped 1 (-1000) = 1 ∧
    repsStepped 1 (-999) = 1 ∧
    repsStepped 1 (-998) = 1 ∧
    repsStepped 1 (-400) = 1 ∧
    repsStepped 1 (-399) = 1 ∧
    repsStepped 1 (-1) = 1 ∧
    repsStepped 1 0 = 1 ∧
    repsStepped 1 1 = 2 ∧
    repsStepped 1 399 = 400 ∧
    repsStepped 1 400 = 401 ∧
    repsStepped 1 998 = 999 ∧
    repsStepped 1 999 = 999 ∧
    repsStepped 1 1000 = 999 ∧
    repsStepped 1 100000 = 999 ∧
    repsStepped 1 9223372036854775807 = 999 := by
  decide +kernel

/-- The repetitions field holds `2`. -/
theorem repsStepped_from2 :
    repsStepped 2 (-9223372036854775808) = 1 ∧
    repsStepped 2 (-100000) = 1 ∧
    repsStepped 2 (-1000) = 1 ∧
    repsStepped 2 (-999) = 1 ∧
    repsStepped 2 (-998) = 1 ∧
    repsStepped 2 (-400) = 1 ∧
    repsStepped 2 (-399) = 1 ∧
    repsStepped 2 (-1) = 1 ∧
    repsStepped 2 0 = 2 ∧
    repsStepped 2 1 = 3 ∧
    repsStepped 2 399 = 401 ∧
    repsStepped 2 400 = 402 ∧
    repsStepped 2 998 = 999 ∧
    repsStepped 2 999 = 999 ∧
    repsStepped 2 1000 = 999 ∧
    repsStepped 2 100000 = 999 ∧
    repsStepped 2 9223372036854775807 = 999 := by
  decide +kernel

/-- The repetitions field holds `5`. -/
theorem repsStepped_from5 :
    repsStepped 5 (-9223372036854775808) = 1 ∧
    repsStepped 5 (-100000) = 1 ∧
    repsStepped 5 (-1000) = 1 ∧
    repsStepped 5 (-999) = 1 ∧
    repsStepped 5 (-998) = 1 ∧
    repsStepped 5 (-400) = 1 ∧
    repsStepped 5 (-399) = 1 ∧
    repsStepped 5 (-1) = 4 ∧
    repsStepped 5 0 = 5 ∧
    repsStepped 5 1 = 6 ∧
    repsStepped 5 399 = 404 ∧
    repsStepped 5 400 = 405 ∧
    repsStepped 5 998 = 999 ∧
    repsStepped 5 999 = 999 ∧
    repsStepped 5 1000 = 999 ∧
    repsStepped 5 100000 = 999 ∧
    repsStepped 5 9223372036854775807 = 999 := by
  decide +kernel

/-- The repetitions field holds `8`. -/
theorem repsStepped_from8 :
    repsStepped 8 (-9223372036854775808) = 1 ∧
    repsStepped 8 (-100000) = 1 ∧
    repsStepped 8 (-1000) = 1 ∧
    repsStepped 8 (-999) = 1 ∧
    repsStepped 8 (-998) = 1 ∧
    repsStepped 8 (-400) = 1 ∧
    repsStepped 8 (-399) = 1 ∧
    repsStepped 8 (-1) = 7 ∧
    repsStepped 8 0 = 8 ∧
    repsStepped 8 1 = 9 ∧
    repsStepped 8 399 = 407 ∧
    repsStepped 8 400 = 408 ∧
    repsStepped 8 998 = 999 ∧
    repsStepped 8 999 = 999 ∧
    repsStepped 8 1000 = 999 ∧
    repsStepped 8 100000 = 999 ∧
    repsStepped 8 9223372036854775807 = 999 := by
  decide +kernel

/-- The repetitions field holds `30`. -/
theorem repsStepped_from30 :
    repsStepped 30 (-9223372036854775808) = 1 ∧
    repsStepped 30 (-100000) = 1 ∧
    repsStepped 30 (-1000) = 1 ∧
    repsStepped 30 (-999) = 1 ∧
    repsStepped 30 (-998) = 1 ∧
    repsStepped 30 (-400) = 1 ∧
    repsStepped 30 (-399) = 1 ∧
    repsStepped 30 (-1) = 29 ∧
    repsStepped 30 0 = 30 ∧
    repsStepped 30 1 = 31 ∧
    repsStepped 30 399 = 429 ∧
    repsStepped 30 400 = 430 ∧
    repsStepped 30 998 = 999 ∧
    repsStepped 30 999 = 999 ∧
    repsStepped 30 1000 = 999 ∧
    repsStepped 30 100000 = 999 ∧
    repsStepped 30 9223372036854775807 = 999 := by
  decide +kernel

/-- The repetitions field holds `999`. -/
theorem repsStepped_from999 :
    repsStepped 999 (-9223372036854775808) = 1 ∧
    repsStepped 999 (-100000) = 1 ∧
    repsStepped 999 (-1000) = 1 ∧
    repsStepped 999 (-999) = 1 ∧
    repsStepped 999 (-998) = 1 ∧
    repsStepped 999 (-400) = 599 ∧
    repsStepped 999 (-399) = 600 ∧
    repsStepped 999 (-1) = 998 ∧
    repsStepped 999 0 = 999 ∧
    repsStepped 999 1 = 999 ∧
    repsStepped 999 399 = 999 ∧
    repsStepped 999 400 = 999 ∧
    repsStepped 999 998 = 999 ∧
    repsStepped 999 999 = 999 ∧
    repsStepped 999 1000 = 999 ∧
    repsStepped 999 100000 = 999 ∧
    repsStepped 999 9223372036854775807 = 999 := by
  decide +kernel

end Gymemo.Stepper.Vectors
