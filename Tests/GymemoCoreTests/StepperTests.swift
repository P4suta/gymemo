import GymemoCore
import Testing

@Suite struct StepperTests {
  @Test func aWeightStepsByTwoAndAHalfKilogramsWithinItsRange() {
    #expect(Weight.stepped(from: "60", by: 1)?.hundredths == 6250)
    #expect(Weight.stepped(from: "60", by: -1)?.hundredths == 5750)
    #expect(Weight.stepped(from: "62,5", by: 2)?.hundredths == 6750)
    #expect(Weight.stepped(from: "", by: 1)?.hundredths == 250)
    #expect(Weight.stepped(from: "", by: -1) == .bodyweight)
    #expect(Weight.stepped(from: "1", by: -1) == .bodyweight)
    #expect(Weight.stepped(from: "999.99", by: 1)?.hundredths == Weight.maximumHundredths)
    #expect(Weight.stepped(from: "abc", by: 1) == nil)
    #expect(Weight.stepped(from: "1.234", by: 1) == nil)
  }

  @Test func repetitionsStepByOneWithinTheirRange() {
    #expect(Reps.stepped(from: "8", by: 1)?.count == 9)
    #expect(Reps.stepped(from: "8", by: -1)?.count == 7)
    #expect(Reps.stepped(from: "1", by: -1) == .one)
    #expect(Reps.stepped(from: "999", by: 1)?.count == Reps.maximumCount)
    #expect(Reps.stepped(from: "", by: 1) == .one)
    #expect(Reps.stepped(from: "", by: -1) == nil)
    #expect(Reps.stepped(from: "x", by: 1) == nil)
  }
}
