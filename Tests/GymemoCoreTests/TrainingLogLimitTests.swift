import GymemoCore
import GymemoTestSupport
import Testing

/// Indexing a million sets takes about a second, so the suite builds the full log once and every test reads it.
/// A failed expectation describes the values that it compared, and describing a full log takes longer than a mutation run waits for a test.
/// Each expectation therefore compares a count that the test read from the log beforehand.
@Suite struct TrainingLogLimitTests {
  /// One exercise more than a log holds.
  private static let exerciseRows: Result<[Exercise], any Error> = Result {
    try (0...UInt32(TrainingLog.maximumExercises)).map { number in
      Exercise(
        id: exerciseID(number), name: try ExerciseName.parse("種目\(number)").get(),
        bodyPart: .other)
    }
  }

  /// The log that `make` builds from exactly as many sets as a log holds.
  private static let logFullOfSets: Result<TrainingLog, any Error> = Result {
    let name = try ExerciseName.parse("懸垂").get()
    let exercise = Exercise(id: exerciseID(1), name: name, bodyPart: .back)
    let sets = (0..<UInt32(TrainingLog.maximumSets)).map(set)
    return try TrainingLog.make(exercises: [exercise], sets: sets, memos: [:]).get()
  }

  /// A set of the one exercise in the full log, which holds the sets numbered below a million.
  private static func set(_ number: UInt32) -> LoggedSet {
    LoggedSet(
      id: setID(number), exerciseID: exerciseID(1), day: .earliest, weight: .bodyweight,
      reps: .one)
  }

  private func adding(_ exercise: Exercise) -> Command {
    .addExercise(id: exercise.id, name: exercise.name.text, bodyPart: exercise.bodyPart)
  }

  private func logging(_ set: LoggedSet) -> Command {
    .logSet(
      id: set.id, exerciseID: set.exerciseID, day: set.day, weight: set.weight, reps: set.reps)
  }

  @Test func buildsALogFromAThousandExercisesAndRefusesOneMore() throws {
    let rows = try Self.exerciseRows.get()
    let atLimit = TrainingLog.make(exercises: Array(rows.dropLast()), sets: [], memos: [:])
      .map(\.exercises.count)
    #expect(atLimit == .success(1000))
    let overLimit = TrainingLog.make(exercises: rows, sets: [], memos: [:]).map(\.exercises.count)
    #expect(overLimit == .failure(.tooManyExercises))
  }

  @Test func addsTheThousandthExerciseAndRefusesOneMore() throws {
    let rows = try Self.exerciseRows.get()
    let oneMore = try #require(rows.last)
    let thousandth = try #require(rows.dropLast().last)
    let almostFull = try TrainingLog.make(
      exercises: Array(rows.dropLast(2)), sets: [], memos: [:]
    ).get()
    let full = try almostFull.applying(adding(thousandth))
    let held = full.exercises.count
    #expect(held == 1000)
    let refused = full.apply(adding(oneMore)).map(\.log.exercises.count)
    #expect(refused == .failure(.full))
  }

  @Test func buildsALogFromAMillionSetsAndRefusesOneMore() throws {
    let full = try Self.logFullOfSets.get()
    let held = full.sets.count
    #expect(held == 1_000_000)
    let overLimit = TrainingLog.make(
      exercises: full.exercises, sets: full.sets + [Self.set(1_000_000)], memos: [:]
    ).map(\.sets.count)
    #expect(overLimit == .failure(.tooManySets))
  }

  @Test func logsTheMillionthSetAndRefusesOneMore() throws {
    let full = try Self.logFullOfSets.get()
    let oneMore = logging(Self.set(1_000_000))
    let refused = full.apply(oneMore).map(\.log.sets.count)
    #expect(refused == .failure(.full))
    let almostFull = try full.applying(.deleteSet(id: setID(0)))
    let refilled = almostFull.apply(oneMore).map(\.log.sets.count)
    #expect(refilled == .success(1_000_000))
  }
}
