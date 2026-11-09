import Gymemo.Stepper

/-!
# The properties of the steppers

`Gymemo/Stepper.lean` states the arithmetic of the two steppers in `Sources/GymemoCore/Weight.swift` over the integers.
The Swift code holds the step count to the width of the range before it multiplies and adds, because 64-bit addition stops the process on overflow.
This file proves that holding the step count changes no result, that every result lies in its range, and that every intermediate value fits in 64 bits for any step count.
-/

namespace Gymemo.Stepper

/-- `held` gives a value between its bounds when the bounds lie in order. -/
private theorem held_range {low high : Int} (value : Int) (ordered : low ≤ high) :
    low ≤ held low high value ∧ held low high value ≤ high :=
  ⟨Int.le_min.mpr ⟨Int.le_max_right value low, ordered⟩, Int.min_le_right (max value low) high⟩

/-- `held` leaves a value between its bounds as it is. -/
private theorem held_of_inside {low high value : Int} (above : low ≤ value)
    (below : value ≤ high) : held low high value = value := by
  unfold held
  rw [Int.max_eq_left above, Int.min_eq_left below]

/-- `held` gives the lower bound for a value at or below it. -/
private theorem held_of_below {low high value : Int} (ordered : low ≤ high)
    (under : value ≤ low) : held low high value = low := by
  unfold held
  rw [Int.max_eq_right under, Int.min_eq_left ordered]

/-- `held` gives the upper bound for a value at or above it. -/
private theorem held_of_above {low high value : Int} (ordered : low ≤ high)
    (over : high ≤ value) : held low high value = high := by
  unfold held
  rw [Int.max_eq_left (Int.le_trans ordered over), Int.min_eq_right over]

/-- A move that grows with the step count gives the same held result for a step count as for that step count held between `least` and `most`, when the move by `least` lies at or below `low` and the move by `most` lies at or above `high`.
A step count beyond `least` or `most` moves at least as far, so both sides give the same bound. -/
private theorem held_move_held {low high least most : Int} {move : Int → Int} (steps : Int)
    (ordered : low ≤ high) (wide : least ≤ most)
    (grows : ∀ fewer more : Int, fewer ≤ more → move fewer ≤ move more)
    (reachesLow : move least ≤ low) (reachesHigh : high ≤ move most) :
    held low high (move (held least most steps)) = held low high (move steps) := by
  cases Int.le_total steps least with
  | inl under =>
    rw [held_of_below wide under, held_of_below ordered reachesLow,
      held_of_below ordered (Int.le_trans (grows steps least under) reachesLow)]
  | inr above =>
    cases Int.le_total most steps with
    | inl over =>
      rw [held_of_above wide over, held_of_above ordered reachesHigh,
        held_of_above ordered (Int.le_trans reachesHigh (grows most steps over))]
    | inr below => rw [held_of_inside above below]

/-- A value between two bounds lies between `-(2 ^ 62)` and `2 ^ 62` when both bounds do. -/
private theorem fits_of_between {least most value : Int} (above : least ≤ value)
    (below : value ≤ most) (leastFits : -(2 ^ 62) < least) (mostFits : most < 2 ^ 62) :
    -(2 ^ 62) < value ∧ value < 2 ^ 62 :=
  ⟨Int.lt_of_lt_of_le leastFits above, Int.lt_of_le_of_lt below mostFits⟩

/-- Holding the step count changes no result: the stepper gives what unbounded arithmetic gives.
The least and the most held step count already move every weight of the range to bodyweight and to the heaviest weight. -/
theorem weightStepped_eq {start steps : Int} (low : 0 ≤ start)
    (high : start ≤ maximumHundredths) :
    weightStepped start steps = held 0 maximumHundredths (start + steps * stepHundredths) := by
  have grows : ∀ fewer more : Int, fewer ≤ more →
      start + fewer * stepHundredths ≤ start + more * stepHundredths :=
    fun _ _ ordered =>
      Int.add_le_add_left (Int.mul_le_mul_of_nonneg_right ordered (by decide)) start
  have reachesLow : start + -maximumHundredths * stepHundredths ≤ 0 :=
    Int.le_trans (Int.add_le_add_right high _) (by decide)
  have reachesHigh : maximumHundredths ≤ start + maximumHundredths * stepHundredths :=
    Int.le_trans (by decide) (Int.add_le_add_right low _)
  exact held_move_held (move := fun counted => start + counted * stepHundredths) steps
    (by decide) (by decide) grows reachesLow reachesHigh

/-- The stepped weight lies between bodyweight and the heaviest weight for any start and any step count. -/
theorem weightStepped_range {start steps : Int} :
    0 ≤ weightStepped start steps ∧ weightStepped start steps ≤ maximumHundredths :=
  held_range _ (by decide)

/-- Every intermediate value of the Swift code fits in 64 bits for any step count.
The Swift code multiplies the held step count by the step and adds the start, and both values lie between `-(2 ^ 62)` and `2 ^ 62`. -/
theorem weightStepped_fits {start steps : Int} (low : 0 ≤ start)
    (high : start ≤ maximumHundredths) :
    -(2 ^ 62) < held (-maximumHundredths) maximumHundredths steps * stepHundredths
      ∧ held (-maximumHundredths) maximumHundredths steps * stepHundredths < 2 ^ 62
      ∧ -(2 ^ 62) < start + held (-maximumHundredths) maximumHundredths steps * stepHundredths
      ∧ start + held (-maximumHundredths) maximumHundredths steps * stepHundredths < 2 ^ 62 := by
  obtain ⟨above, below⟩ :=
    held_range steps (show -maximumHundredths ≤ maximumHundredths by decide)
  generalize held (-maximumHundredths) maximumHundredths steps = counted at above below ⊢
  have down : -maximumHundredths * stepHundredths ≤ counted * stepHundredths :=
    Int.mul_le_mul_of_nonneg_right above (by decide)
  have up : counted * stepHundredths ≤ maximumHundredths * stepHundredths :=
    Int.mul_le_mul_of_nonneg_right below (by decide)
  have product := fits_of_between down up (by decide) (by decide)
  have sum := fits_of_between (Int.add_le_add low down) (Int.add_le_add high up)
    (by decide) (by decide)
  exact ⟨product.1, product.2, sum.1, sum.2⟩

/-- Holding the step count changes no result: the stepper gives what unbounded arithmetic gives.
The start is a count of the range or the zero that an empty field starts at, and the least and the most held step count already move every such start to one and to the largest count. -/
theorem repsStepped_eq {start steps : Int} (low : 0 ≤ start) (high : start ≤ maximumCount) :
    repsStepped start steps = held 1 maximumCount (start + steps) := by
  have grows : ∀ fewer more : Int, fewer ≤ more → start + fewer ≤ start + more :=
    fun _ _ ordered => Int.add_le_add_left ordered start
  have reachesLow : start + -maximumCount ≤ 1 :=
    Int.le_trans (Int.add_le_add_right high _) (by decide)
  have reachesHigh : maximumCount ≤ start + maximumCount :=
    Int.le_trans (by decide) (Int.add_le_add_right low _)
  exact held_move_held (move := fun counted => start + counted) steps
    (by decide) (by decide) grows reachesLow reachesHigh

/-- The stepped count lies between one and the largest count for any start and any step count. -/
theorem repsStepped_range {start steps : Int} :
    1 ≤ repsStepped start steps ∧ repsStepped start steps ≤ maximumCount :=
  held_range _ (by decide)

/-- The sum of the Swift code fits in 64 bits for any step count.
The Swift code adds the held step count to the start, and the sum lies between `-(2 ^ 62)` and `2 ^ 62`. -/
theorem repsStepped_fits {start steps : Int} (low : 0 ≤ start) (high : start ≤ maximumCount) :
    -(2 ^ 62) < start + held (-maximumCount) maximumCount steps
      ∧ start + held (-maximumCount) maximumCount steps < 2 ^ 62 := by
  obtain ⟨above, below⟩ := held_range steps (show -maximumCount ≤ maximumCount by decide)
  exact fits_of_between (Int.add_le_add low above) (Int.add_le_add high below)
    (by decide) (by decide)

end Gymemo.Stepper
