import GymemoCore
import GymemoTestSupport
import Testing

@Suite struct CompanionCatalogTests {
  @Test func recentVisibleExercisesComeFirstWithTheirLatestSet() throws {
    let exercise = try #require(TrainingLog.starter.exercises.last)
    let archived = try #require(TrainingLog.starter.exercises.first)
    let set = LoggedSet(
      id: setID(1), exerciseID: exercise.id, day: try #require(LocalDay(iso: "2026-11-09")),
      weight: .bodyweight, reps: .one)
    let added = try TrainingLog.starter.apply(
      .logSet(
        id: set.id, exerciseID: set.exerciseID, day: set.day, weight: set.weight, reps: set.reps)
    ).get().log
    let log = try added.apply(.setExerciseArchived(id: archived.id, isArchived: true)).get().log
    let catalog = CompanionCatalog(log: log)
    #expect(catalog.exercises.first?.exercise == exercise)
    #expect(catalog.exercises.first?.suggestion == SetEntry(weight: .bodyweight, reps: .one))
    #expect(!catalog.exercises.contains { $0.id == archived.id })
    #expect(catalog.exercises.dropFirst().allSatisfy { $0.suggestion == nil })
    #expect(CompanionCatalog(exercises: catalog.exercises) == catalog)
    #expect(CompanionCatalog(exercises: []) == CompanionCatalog(log: .empty))
  }

  @Test func aCatalogRefusesDuplicatesHiddenExercisesAndAnOversizedList() throws {
    let first = CompanionCatalog(log: .starter).exercises[0]
    #expect(CompanionCatalog(exercises: [first, first]) == nil)
    var hidden = first.exercise
    hidden.isArchived = true
    #expect(
      CompanionCatalog(exercises: [CompanionExercise(exercise: hidden, suggestion: nil)]) == nil)
    let renamedID = Exercise(
      id: exerciseID(999), name: first.exercise.name, bodyPart: first.exercise.bodyPart)
    #expect(
      CompanionCatalog(exercises: [first, CompanionExercise(exercise: renamedID, suggestion: nil)])
        == nil)
    var exercises: [Exercise] = []
    for index in 0...CompanionCatalog.maximumExercises {
      let name = try ExerciseName.parse("Exercise \(index)").get()
      exercises.append(Exercise(id: exerciseID(UInt32(index)), name: name, bodyPart: .other))
    }
    let log = try TrainingLog.make(exercises: exercises, sets: [], memos: [:]).get()
    #expect(CompanionCatalog(log: log).exercises.map(\.exercise) == Array(exercises.prefix(40)))
    let maximum = exercises.prefix(CompanionCatalog.maximumExercises).map {
      CompanionExercise(exercise: $0, suggestion: nil)
    }
    #expect(CompanionCatalog(exercises: maximum)?.exercises == maximum)
    #expect(
      CompanionCatalog(
        exercises: exercises.map { CompanionExercise(exercise: $0, suggestion: nil) }) == nil)
  }
}
