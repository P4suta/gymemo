import Gymemo.Strength

/-!
# The properties of the estimated one-repetition load

`Gymemo/Strength.lean` states the arithmetic of `Sources/GymemoCore/Strength.swift` over natural numbers.
This file proves that the stored integer is Epley's estimate exactly, that the estimate grows with the weight and with the repetitions, that `tenths` rounds to the nearest tenth of a kilogram, and that every value stays far below the limit of a 64-bit integer.
-/

namespace Gymemo.Strength

/-- The number that `units` multiplies a weight by, which is Epley's factor in thirtieths. -/
private def multiplier (reps : Nat) : Nat :=
  if reps = 1 then 30 else 30 + reps

/-- `units` is the weight times the multiplier of the repetitions. -/
private theorem units_eq (hundredths reps : Nat) :
    units hundredths reps = hundredths * multiplier reps :=
  rfl

/-- A single repetition multiplies the weight by 30. -/
private theorem multiplier_single : multiplier 1 = 30 :=
  rfl

/-- Any other repetition count multiplies the weight by 30 plus the count. -/
private theorem multiplier_several {reps : Nat} (several : reps ≠ 1) :
    multiplier reps = 30 + reps :=
  ite_eq_right several

/-- The multiplier is positive for every repetition count. -/
private theorem multiplier_pos (reps : Nat) : 0 < multiplier reps := by
  unfold multiplier
  split
  · decide
  · exact Nat.add_pos_left (by decide) reps

/-- The multiplier is at most 30 plus the repetition count. -/
private theorem multiplier_le (reps : Nat) : multiplier reps ≤ 30 + reps := by
  unfold multiplier
  split
  · exact Nat.le_add_right 30 reps
  · exact Nat.le_refl (30 + reps)

/-- The multiplier grows with the repetitions from one repetition on.
The larger count is more than one, so its multiplier is 30 plus that count, and the smaller multiplier stays below it. -/
private theorem multiplier_lt_of_lt {fewer more : Nat} (counted : 1 ≤ fewer)
    (grows : fewer < more) : multiplier fewer < multiplier more := by
  have several : more ≠ 1 := Nat.ne_of_gt (Nat.lt_of_le_of_lt counted grows)
  rw [multiplier_several several]
  exact Nat.lt_of_le_of_lt (multiplier_le fewer) (Nat.add_lt_add_left grows 30)

/-- For more than one repetition the stored integer equals Epley's estimate, the weight times one plus the repetitions over 30, exactly.
In kilograms the claim is `units / 3000 = (hundredths / 100) * (30 + reps) / 30`, and the statement clears the denominators 3000, 100, and 30 to stay within the natural numbers. -/
theorem units_epley {hundredths reps : Nat} (several : reps ≠ 1) :
    units hundredths reps * 100 * 30 = hundredths * (30 + reps) * 3000 := by
  rw [units_eq, multiplier_several several]
  exact Nat.mul_assoc (hundredths * (30 + reps)) 100 30

/-- A single repetition keeps its weight.
In kilograms the claim is `units / 3000 = hundredths / 100`. -/
theorem units_single {hundredths : Nat} : units hundredths 1 * 100 = hundredths * 3000 := by
  rw [units_eq, multiplier_single]
  exact Nat.mul_assoc hundredths 30 100

/-- The estimate grows with more weight at the same repetition count. -/
theorem units_lt_of_weight_lt {lighter heavier reps : Nat} (more : lighter < heavier) :
    units lighter reps < units heavier reps := by
  rw [units_eq, units_eq]
  exact Nat.mul_lt_mul_of_pos_right more (multiplier_pos reps)

/-- The estimate grows with more repetitions, also from one repetition to two.
The Swift code gives no estimate to a set without added weight, and the model gives such a set zero units for every count, so the weight is positive here. -/
theorem units_lt_of_reps_lt {hundredths fewer more : Nat} (loaded : 0 < hundredths)
    (counted : 1 ≤ fewer) (grows : fewer < more) :
    units hundredths fewer < units hundredths more := by
  rw [units_eq, units_eq]
  exact Nat.mul_lt_mul_of_pos_left (multiplier_lt_of_lt counted grows) loaded

/-- `tenths` is the nearest tenth of a kilogram with a half rounded up, where 300 units are one tenth.
The value lies from half a tenth below `tenths` up to, but not at, half a tenth above it. -/
theorem tenths_nearest {value : Nat} :
    300 * tenths value ≤ value + 150 ∧ value + 150 < 300 * tenths value + 300 :=
  have floor : 300 * tenths value ≤ value + 150 := Nat.mul_div_le (value + 150) 300
  have next : value + 150 < 300 * (tenths value + 1) :=
    Nat.lt_mul_div_succ (value + 150) (by decide)
  ⟨floor, next⟩

/-- No value of the Swift code's 64-bit arithmetic overflows.
The largest estimate is 99999 times 1029 units, and the 150 that `tenths` adds for rounding leaves it far below `2 ^ 62`. -/
theorem units_bound {hundredths reps : Nat} (weight : hundredths ≤ maximumHundredths)
    (count : reps ≤ maximumCount) : units hundredths reps + 150 < 2 ^ 62 := by
  have largest : multiplier reps ≤ 30 + maximumCount :=
    Nat.le_trans (multiplier_le reps) (Nat.add_le_add_left count 30)
  have product : units hundredths reps ≤ maximumHundredths * (30 + maximumCount) :=
    Nat.mul_le_mul weight largest
  exact Nat.lt_of_le_of_lt (Nat.add_le_add_right product 150) (by decide)

end Gymemo.Strength
