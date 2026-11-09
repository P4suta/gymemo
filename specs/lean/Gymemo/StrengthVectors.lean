import Gymemo.Strength

/-!
# Results of the Swift code for the estimated one-repetition load

`Tests/GymemoCoreTests/LeanVectors.swift` writes this file from what `OneRepMax.estimate` returns, and `mise x -- just gen` runs it.
A package test fails while this file differs from those results, so no change by hand lasts.
After `mise x -- just gen`, `lake build --wfail` in `specs/lean` checks the theorems.
Each line holds when `tenths (units weight reps)` of `Gymemo/Strength.lean` gives the `tenths` of the Swift estimate for a weight in hundredths of a kilogram.
A set without added weight has no estimate in the Swift code, so no line starts from a weight of zero.
-/

namespace Gymemo.Strength.Vectors

/-- The limits of `Weight` and `Reps`. -/
theorem limits :
    maximumHundredths = 99999 ∧
    maximumCount = 999 := by
  decide +kernel

/-- The estimates of 0.01 kg. -/
theorem tenths_units_1 :
    tenths (units 1 1) = 0 ∧
    tenths (units 1 2) = 0 ∧
    tenths (units 1 5) = 0 ∧
    tenths (units 1 7) = 0 ∧
    tenths (units 1 8) = 0 ∧
    tenths (units 1 10) = 0 ∧
    tenths (units 1 30) = 0 ∧
    tenths (units 1 999) = 3 := by
  decide +kernel

/-- The estimates of 0.04 kg. -/
theorem tenths_units_4 :
    tenths (units 4 1) = 0 ∧
    tenths (units 4 2) = 0 ∧
    tenths (units 4 5) = 0 ∧
    tenths (units 4 7) = 0 ∧
    tenths (units 4 8) = 1 ∧
    tenths (units 4 10) = 1 ∧
    tenths (units 4 30) = 1 ∧
    tenths (units 4 999) = 14 := by
  decide +kernel

/-- The estimates of 0.05 kg. -/
theorem tenths_units_5 :
    tenths (units 5 1) = 1 ∧
    tenths (units 5 2) = 1 ∧
    tenths (units 5 5) = 1 ∧
    tenths (units 5 7) = 1 ∧
    tenths (units 5 8) = 1 ∧
    tenths (units 5 10) = 1 ∧
    tenths (units 5 30) = 1 ∧
    tenths (units 5 999) = 17 := by
  decide +kernel

/-- The estimates of 0.77 kg. -/
theorem tenths_units_77 :
    tenths (units 77 1) = 8 ∧
    tenths (units 77 2) = 8 ∧
    tenths (units 77 5) = 9 ∧
    tenths (units 77 7) = 9 ∧
    tenths (units 77 8) = 10 ∧
    tenths (units 77 10) = 10 ∧
    tenths (units 77 30) = 15 ∧
    tenths (units 77 999) = 264 := by
  decide +kernel

/-- The estimates of 2.5 kg. -/
theorem tenths_units_250 :
    tenths (units 250 1) = 25 ∧
    tenths (units 250 2) = 27 ∧
    tenths (units 250 5) = 29 ∧
    tenths (units 250 7) = 31 ∧
    tenths (units 250 8) = 32 ∧
    tenths (units 250 10) = 33 ∧
    tenths (units 250 30) = 50 ∧
    tenths (units 250 999) = 858 := by
  decide +kernel

/-- The estimates of 60 kg. -/
theorem tenths_units_6000 :
    tenths (units 6000 1) = 600 ∧
    tenths (units 6000 2) = 640 ∧
    tenths (units 6000 5) = 700 ∧
    tenths (units 6000 7) = 740 ∧
    tenths (units 6000 8) = 760 ∧
    tenths (units 6000 10) = 800 ∧
    tenths (units 6000 30) = 1200 ∧
    tenths (units 6000 999) = 20580 := by
  decide +kernel

/-- The estimates of 62.5 kg. -/
theorem tenths_units_6250 :
    tenths (units 6250 1) = 625 ∧
    tenths (units 6250 2) = 667 ∧
    tenths (units 6250 5) = 729 ∧
    tenths (units 6250 7) = 771 ∧
    tenths (units 6250 8) = 792 ∧
    tenths (units 6250 10) = 833 ∧
    tenths (units 6250 30) = 1250 ∧
    tenths (units 6250 999) = 21438 := by
  decide +kernel

/-- The estimates of 999.99 kg. -/
theorem tenths_units_99999 :
    tenths (units 99999 1) = 10000 ∧
    tenths (units 99999 2) = 10667 ∧
    tenths (units 99999 5) = 11667 ∧
    tenths (units 99999 7) = 12333 ∧
    tenths (units 99999 8) = 12667 ∧
    tenths (units 99999 10) = 13333 ∧
    tenths (units 99999 30) = 20000 ∧
    tenths (units 99999 999) = 342997 := by
  decide +kernel

end Gymemo.Strength.Vectors
