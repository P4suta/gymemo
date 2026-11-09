/-!
# The steppers of a weight and of a repetition count

`Sources/GymemoCore/Weight.swift` moves a weight by steps of 2.5 kg and a repetition count by steps of one, and holds each result in its range.
The Swift code adds 64-bit integers, which stop the process on overflow, so it first holds the step count to the width of the range.
This file states the same arithmetic over the integers.
-/

namespace Gymemo.Stepper

/-- The heaviest weight in hundredths of a kilogram, as `Weight.maximumHundredths`. -/
def maximumHundredths : Int := 99999

/-- One step of a weight stepper in hundredths of a kilogram, as `Weight.stepHundredths`. -/
def stepHundredths : Int := 250

/-- The largest repetition count, as `Reps.maximumCount`. -/
def maximumCount : Int := 999

/-- `min(max(value, low), high)`. -/
def held (low high value : Int) : Int :=
  min (max value low) high

/-- `Weight.stepped` from a start in hundredths of a kilogram. -/
def weightStepped (start steps : Int) : Int :=
  held 0 maximumHundredths
    (start + held (-maximumHundredths) maximumHundredths steps * stepHundredths)

/-- `Reps.stepped` from a count, where an empty field that steps up starts at zero. -/
def repsStepped (start steps : Int) : Int :=
  held 1 maximumCount (start + held (-maximumCount) maximumCount steps)

end Gymemo.Stepper
