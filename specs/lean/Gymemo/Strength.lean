/-!
# The estimated one-repetition load

`Sources/GymemoCore/Strength.swift` keeps Epley's estimate in units of 1/3000 kg, so that every comparison is exact.
This file states the same arithmetic over natural numbers.
-/

namespace Gymemo.Strength

/-- The heaviest weight in hundredths of a kilogram, as `Weight.maximumHundredths`. -/
def maximumHundredths : Nat := 99999

/-- The largest repetition count, as `Reps.maximumCount`. -/
def maximumCount : Nat := 999

/-- The integer that `OneRepMax.estimate` stores for a set with added weight, in units of 1/3000 kg, for a weight in hundredths of a kilogram.
A single repetition keeps its weight, and more repetitions give the weight times one plus the repetitions over 30.
A set without added weight has no estimate in the Swift code, so the theorems take a positive weight where the difference matters. -/
def units (hundredths reps : Nat) : Nat :=
  hundredths * (if reps = 1 then 30 else 30 + reps)

/-- `OneRepMax.tenths`: tenths of a kilogram, rounded half up. -/
def tenths (units : Nat) : Nat :=
  (units + 150) / 300

end Gymemo.Strength
