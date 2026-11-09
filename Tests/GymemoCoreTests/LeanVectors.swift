import Foundation
import GymemoCore
import GymemoTestSupport

/// A value of the Swift code that the Lean model has no term for.
enum VectorFault: Error, Equatable {
  /// An identifier that `uuid(_:)` of the test support didn't write.
  case foreignIdentifier(UUID)
  /// A weight or a repetition count of a grid that lies outside its range.
  case outOfRange(Int)
  /// A weight that has no estimate.
  case noEstimate(hundredths: Int)
  /// A text of a grid that a stepper doesn't step from.
  case noStep(from: String, by: Int)
  /// Rows or a command whose theorem has no tactics here.
  case noProof(String)
}

/// The number of sets below which Lean's kernel decides a theorem about a log that no definition names.
/// `make` over a thousand distinct exercises ran out of the memory of the proof run.
private let kernelRows = 1_000

/// Whether two logs hold the same rows, which decide a log, because the indexes of a log of a million sets take long to compare.
private func sameRows(_ one: TrainingLog, _ other: TrainingLog) -> Bool {
  one.exercises == other.exercises && one.sets == other.sets && one.memos == other.memos
}

/// The number that `uuid(_:)` wrote into the last four bytes of an identifier, or nothing for an identifier of another origin.
private func identifierNumber(_ identifier: UUID) -> UInt32? {
  let bytes = identifier.uuid
  let number = [bytes.12, bytes.13, bytes.14, bytes.15].reduce(UInt32(0)) { number, byte in
    number << 8 | UInt32(byte)
  }
  return uuid(number) == identifier ? number : nil
}

/// Sets whose identifiers count up by one and whose other fields agree, which a Lean file writes as `(List.range count).map`, so that a million sets take one line.
private struct SetRun {
  let first: UInt32
  let count: Int
  let template: LoggedSet

  init?(_ sets: [LoggedSet]) {
    guard sets.count > 8, let head = sets.first, let first = identifierNumber(head.id.uuid) else {
      return nil
    }
    for (offset, set) in sets.enumerated() {
      guard let number = UInt32(exactly: Int(first) + offset),
        set
          == LoggedSet(
            id: setID(number), exerciseID: head.exerciseID, day: head.day, weight: head.weight,
            reps: head.reps)
      else { return nil }
    }
    self.first = first
    count = sets.count
    template = head
  }

  func contains(_ number: UInt32) -> Bool {
    number >= first && Int(number - first) < count
  }
}

/// The numbers that stand for values in a Lean file, in the order of first use.
struct Numbering<Value: Hashable> {
  private(set) var values: [Value] = []
  private var numbers: [Value: Int] = [:]

  mutating func number(of value: Value) -> Int {
    if let known = numbers[value] { return known }
    numbers[value] = values.count
    values.append(value)
    return values.count - 1
  }
}

/// What a command sequence gave from the empty log, one command after another.
struct Walk {
  let commands: [Command]
  /// The log that each command met.
  let logs: [TrainingLog]
  let results: [Result<Transition, Refusal>]
  let final: TrainingLog
  /// The positions of the commands after which the stored rows or the rebuilt log differed from the log.
  let broken: [Int]

  init(_ commands: [Command]) {
    var log = TrainingLog.empty
    var rows = RowModel()
    var logs: [TrainingLog] = []
    var results: [Result<Transition, Refusal>] = []
    var broken: [Int] = []
    for (position, command) in commands.enumerated() {
      logs.append(log)
      let result = log.apply(command)
      results.append(result)
      guard case .success(let transition) = result else { continue }
      log = transition.log
      rows.store(transition.changes)
      let rebuilt = TrainingLog.make(exercises: log.exercises, sets: log.sets, memos: log.memos)
      if rebuilt != .success(log) || rows != RowModel(log) { broken.append(position) }
    }
    self.commands = commands
    self.logs = logs
    self.results = results
    self.broken = broken
    final = log
  }

  var accepted: Int {
    results.count { result in
      if case .success = result { true } else { false }
    }
  }
}

/// A Lean integer, which needs parentheses below zero.
private func integer(_ value: Int) -> String {
  value < 0 ? "(\(value))" : "\(value)"
}

/// A Lean list with one term on each line.
private func tall(_ terms: [String]) -> String {
  terms.isEmpty ? "[]" : "[\n" + terms.map { "  \($0)" }.joined(separator: ",\n") + "\n]"
}

/// A Lean list on lines of about a hundred characters.
private func wrapped(_ terms: [String]) -> String {
  var rows: [String] = []
  var row = ""
  for term in terms {
    if !row.isEmpty && row.count + term.count > 94 {
      rows.append(row + ",")
      row = ""
    }
    row += row.isEmpty ? term : ", \(term)"
  }
  rows.append(row)
  return "[" + rows.joined(separator: "\n   ") + "]"
}

/// A text between quotes, where an escape stands for each character other than a letter or a visible ASCII character.
private func quoted(_ text: String) -> String {
  let letters: Set<Unicode.GeneralCategory> = [
    .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
  ]
  var quoted = "\""
  for scalar in text.unicodeScalars {
    switch scalar {
    case "\"": quoted += "\\\""
    case "\\": quoted += "\\\\"
    case "\n": quoted += "\\n"
    case " "..."~": quoted.unicodeScalars.append(scalar)
    case _ where letters.contains(scalar.properties.generalCategory):
      quoted.unicodeScalars.append(scalar)
    default: quoted += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
    }
  }
  return quoted + "\""
}

/// The table that gives the text of each number, as the lines of a comment.
private func table(_ title: String, _ texts: [String]) -> String {
  let rows = texts.enumerated().map { number, text in "--   \(number) \(quoted(text))" }
  return (["-- \(title)"] + rows).joined(separator: "\n")
}

/// A theorem that holds every line at once, which Lean's kernel decides unless the caller gives other tactics.
private func theorem(
  _ name: String, _ summary: String, _ lines: [String], tactics: [String] = ["decide +kernel"]
) -> String {
  """
  /-- \(summary) -/
  theorem \(name) :
      \(lines.joined(separator: " ∧\n    ")) := by
    \(tactics.joined(separator: "\n  "))
  """
}

/// A Lean list on one line, where `List.replicate` stands for a long run of one row, so that a run of a million rows takes one term.
private func flat<Row: Equatable>(_ rows: [Row], _ term: (Row) throws -> String) rethrows -> String
{
  if rows.count > 8, let first = rows.first, rows.allSatisfy({ $0 == first }) {
    return "List.replicate \(rows.count) \(try term(first))"
  }
  return "[\(try rows.map(term).joined(separator: ", "))]"
}

/// A Lean file of vectors: its import, a comment that names its origin, and its declarations in a namespace.
private func file(
  module: String, title: String, origin: String, notes: String, tables: [String] = [],
  declarations: [String]
) -> String {
  let comment = """
    import \(module)

    /-!
    # \(title)

    `Tests/GymemoCoreTests/LeanVectors.swift` writes this file from what \(origin), \
    and `mise x -- just gen` runs it.
    A package test fails while this file differs from those results, so no change by hand lasts.
    After `mise x -- just gen`, `lake build --wfail` in `specs/lean` checks the theorems.
    \(notes)
    -/
    """
  let parts =
    [comment] + tables + ["namespace \(module).Vectors"] + declarations
    + ["end \(module).Vectors"]
  return parts.joined(separator: "\n\n") + "\n"
}

/// Writes values of the Swift code as terms of `Gymemo/Log.lean`, and numbers the names and the memo texts.
struct LogTerms {
  private(set) var names = Numbering<ExerciseName>()
  private(set) var memos = Numbering<Memo>()
  /// The logs that the file defines by name, with the run of their sets.
  private var definitions: [(name: String, log: TrainingLog, run: SetRun?)] = []

  /// The number that `uuid(_:)` wrote into the last four bytes of an identifier.
  private func numeral(_ identifier: UUID) throws -> UInt32 {
    guard let number = identifierNumber(identifier) else {
      throw VectorFault.foreignIdentifier(identifier)
    }
    return number
  }

  private func number(_ identifier: UUID) throws -> String { "\(try numeral(identifier))" }

  private func day(_ day: LocalDay) -> String { integer(day.dayNumber) }

  private func nameRefusal(_ refusal: ExerciseNameRefusal) -> String {
    switch refusal {
    case .empty: ".empty"
    case .tooLong: ".tooLong"
    case .controlCharacter: ".controlCharacter"
    }
  }

  private func memoRefusal(_ refusal: MemoRefusal) -> String {
    switch refusal {
    case .tooLong: ".tooLong"
    case .controlCharacter: ".controlCharacter"
    }
  }

  private func refusal(_ refusal: Refusal) -> String {
    switch refusal {
    case .exerciseName(let refusal): "(.exerciseName \(nameRefusal(refusal)))"
    case .duplicateExerciseName: ".duplicateExerciseName"
    case .duplicateIdentifier: ".duplicateIdentifier"
    case .unknownExercise: ".unknownExercise"
    case .exerciseHasSets: ".exerciseHasSets"
    case .unknownSet: ".unknownSet"
    case .memo(let refusal): "(.memo \(memoRefusal(refusal)))"
    case .full: ".full"
    }
  }

  /// What `TrainingLog.make` gives: its refusal, or nothing for rows that form a log.
  func made(_ result: Result<TrainingLog, IntegrityRefusal>) -> String {
    switch result {
    case .success: "none"
    case .failure(.duplicateExerciseID): "some .duplicateExerciseID"
    case .failure(.duplicateExerciseName): "some .duplicateExerciseName"
    case .failure(.duplicateSetID): "some .duplicateSetID"
    case .failure(.unknownExercise): "some .unknownExercise"
    case .failure(.tooManyExercises): "some .tooManyExercises"
    case .failure(.tooManySets): "some .tooManySets"
    }
  }

  /// What `ExerciseName.parse` makes of a command's text.
  private mutating func nameInput(_ text: String) -> String {
    switch ExerciseName.parse(text) {
    case .success(let name): "(.accepted \(names.number(of: name)))"
    case .failure(let refusal): "(.refused \(nameRefusal(refusal)))"
    }
  }

  /// What `Memo.parse` makes of a command's text.
  private mutating func memoInput(_ text: String) -> String {
    switch Memo.parse(text) {
    case .success(.some(let memo)): "(.kept \(memos.number(of: memo)))"
    case .success(.none): ".nothing"
    case .failure(let refusal): "(.refused \(memoRefusal(refusal)))"
    }
  }

  private mutating func exercise(_ exercise: Exercise) throws -> String {
    let fields = [
      try number(exercise.id.uuid), "\(names.number(of: exercise.name))",
      ".\(exercise.bodyPart.rawValue)", "\(exercise.isArchived)",
    ]
    return "⟨\(fields.joined(separator: ", "))⟩"
  }

  private func set(_ set: LoggedSet) throws -> String {
    let fields = [
      try number(set.id.uuid), try number(set.exerciseID.uuid), day(set.day),
      "\(set.weight.hundredths)", "\(set.reps.count)",
    ]
    return "⟨\(fields.joined(separator: ", "))⟩"
  }

  /// A run of sets as the sets of its numbers.
  private func run(_ run: SetRun) throws -> String {
    let set = run.template
    let fields = [
      "i + \(run.first)", try number(set.exerciseID.uuid), day(set.day), "\(set.weight.hundredths)",
      "\(set.reps.count)",
    ]
    return "(List.range \(run.count)).map (fun (i : Nat) => ⟨\(fields.joined(separator: ", "))⟩)"
  }

  /// The memos of a log in the order of their days.
  private mutating func memoTerms(_ memos: [LocalDay: Memo]) -> [String] {
    memos.sorted { $0.key < $1.key }.map { "(\(day($0.key)), \(self.memos.number(of: $0.value)))" }
  }

  /// Rows of any origin on one line.
  mutating func rows(
    exercises: [Exercise], sets: [LoggedSet], memos: [LocalDay: Memo]
  ) throws -> String {
    let lists = [
      try flat(exercises) { try exercise($0) },
      try SetRun(sets).map(run) ?? flat(sets) { try set($0) }, flat(memoTerms(memos)) { $0 },
    ]
    return "⟨\(lists.joined(separator: ", "))⟩"
  }

  /// The definition of a log by name, which commands and changes name in place of its rows from then on.
  /// Lean recurses through a list once for each row and more, and a list of a thousand rows went past a depth of 8192.
  mutating func define(_ name: String, _ log: TrainingLog) throws -> String {
    let run = SetRun(log.sets)
    let term = try spread(log, run: run)
    definitions.append((name, log, run))
    return "set_option maxRecDepth 32768 in\ndef \(name) : Log := \(term)"
  }

  private func definition(of log: TrainingLog) -> (name: String, log: TrainingLog, run: SetRun?)? {
    definitions.first { sameRows($0.log, log) }
  }

  /// A log on one line, or the name of its definition.
  mutating func log(_ log: TrainingLog) throws -> String {
    if let defined = definition(of: log) { return defined.name }
    return try rows(exercises: log.exercises, sets: log.sets, memos: log.memos)
  }

  /// A log with each of its lists on lines of its own.
  mutating func spread(_ log: TrainingLog) throws -> String {
    try spread(log, run: SetRun(log.sets))
  }

  private mutating func spread(_ log: TrainingLog, run sets: SetRun?) throws -> String {
    let lists = [
      wrapped(try log.exercises.map { try exercise($0) }),
      try sets.map(run) ?? wrapped(try log.sets.map { try set($0) }),
      wrapped(memoTerms(log.memos)),
    ]
    return "⟨\n  " + lists.joined(separator: ",\n  ") + "⟩"
  }

  mutating func command(_ command: Command) throws -> String {
    switch command {
    case .addExercise(let id, let name, let bodyPart):
      try ".addExercise \(number(id.uuid)) \(nameInput(name)) .\(bodyPart.rawValue)"
    case .editExercise(let id, let name, let bodyPart):
      try ".editExercise \(number(id.uuid)) \(nameInput(name)) .\(bodyPart.rawValue)"
    case .setExerciseArchived(let id, let isArchived):
      try ".setExerciseArchived \(number(id.uuid)) \(isArchived)"
    case .deleteExercise(let id):
      try ".deleteExercise \(number(id.uuid))"
    case .logSet(let id, let exerciseID, let day, let weight, let reps):
      try ".logSet \(number(id.uuid)) \(number(exerciseID.uuid)) \(self.day(day)) "
        + "\(weight.hundredths) \(reps.count)"
    case .editSet(let id, let weight, let reps):
      try ".editSet \(number(id.uuid)) \(weight.hundredths) \(reps.count)"
    case .deleteSet(let id):
      try ".deleteSet \(number(id.uuid))"
    case .writeMemo(let day, let text):
      ".writeMemo \(self.day(day)) \(memoInput(text))"
    case .replaceAll(let log):
      try ".replaceAll \(self.log(log))"
    }
  }

  private mutating func change(_ change: Change) throws -> String {
    switch change {
    case .putExercise(let exercise): try ".putExercise \(self.exercise(exercise))"
    case .removeExercise(let id): try ".removeExercise \(number(id.uuid))"
    case .putSet(let set): try ".putSet \(self.set(set))"
    case .removeSet(let id): try ".removeSet \(number(id.uuid))"
    case .putMemo(let day, let memo): ".putMemo \(self.day(day)) \(memos.number(of: memo))"
    case .removeMemo(let day): ".removeMemo \(self.day(day))"
    case .replaceAll(let log): try ".replaceAll \(self.log(log))"
    }
  }

  /// The refusal of a command, or the changes that it returned.
  mutating func step(_ result: Result<Transition, Refusal>) throws -> String {
    switch result {
    case .failure(let refusal):
      return ".refused \(self.refusal(refusal))"
    case .success(let transition):
      let changes = try transition.changes.map { try change($0) }
      return ".changed [\(changes.joined(separator: ", "))]"
    }
  }

  /// What `apply` gives: the refusal of a command, or the log after it with its changes.
  mutating func outcome(_ result: Result<Transition, Refusal>) throws -> String {
    switch result {
    case .failure(let refusal):
      return ".refused \(self.refusal(refusal))"
    case .success(let transition):
      let changes = try transition.changes.map { try change($0) }
      return ".accepted ⟨\(try log(transition.log)), [\(changes.joined(separator: ", "))]⟩"
    }
  }

  /// The tactics that prove what one command gives.
  /// Lean's kernel can't search or compare a million sets, so a replacement holds by `rfl`.
  /// A set logged into a run rewrites what the model reads of the run: its exercise, its identifier, or the count of the sets.
  /// The kernel then decides from numbers alone.
  mutating func tactics(
    _ log: TrainingLog, _ command: Command, _ result: Result<Transition, Refusal>
  ) throws -> [String] {
    if case .replaceAll = command { return ["rfl"] }
    guard let defined = definition(of: log), let run = defined.run else {
      guard log.sets.count < kernelRows else {
        throw VectorFault.noProof("\(command)")
      }
      return ["decide +kernel"]
    }
    guard case .logSet(let id, let exerciseID, let day, let weight, let reps) = command else {
      throw VectorFault.noProof("\(command)")
    }
    let name = defined.name
    let number = try numeral(id.uuid)
    var tactics = [
      "have exercise : (\(name).exercise? \(try self.number(exerciseID.uuid))).isNone = "
        + "\(log.exercise(exerciseID) == nil) := by decide +kernel"
    ]
    if run.contains(number) {
      tactics += [
        "have set : (\(name).set? \(number)).isSome = true := by",
        "  simp only [Log.set?, \(name), List.find?_isSome, List.mem_map, List.mem_range]",
        "  exact ⟨_, ⟨\(number - run.first), by decide, rfl⟩, by decide⟩",
      ]
    } else {
      tactics += [
        "have set : \(name).set? \(number) = none := by",
        "  simp only [Log.set?, \(name), List.find?_eq_none, List.mem_map, List.mem_range]",
        "  intro set ⟨i, bound, made⟩", "  subst made", "  simp only [beq_iff_eq]",
        "  show ¬(i + \(run.first) = \(number))", "  omega",
      ]
    }
    tactics += [
      "have count : \(name).sets.length = \(run.count) := by",
      "  simp only [\(name), List.length_map, List.length_range]",
    ]
    guard case .success(let transition) = result else {
      return tactics + ["simp only [apply, logSet, exercise, set, count]", "all_goals decide"]
    }
    // The log after the set is the run before it with the set appended, which `List.range_succ` shows without counting the run.
    let logged = LoggedSet(id: id, exerciseID: exerciseID, day: day, weight: weight, reps: reps)
    let unfolded = [name] + (definition(of: transition.log).map { [$0.name] } ?? [])
    return tactics + [
      "have grown :",
      "    \(try self.log(transition.log)) =",
      "      { \(name) with sets := \(name).sets ++ [\(try set(logged))] } := by",
      "  simp only [\(unfolded.joined(separator: ", ")), List.range_succ (n := \(run.count)), "
        + "List.map_append, List.map_cons, List.map_nil]",
      "simp only [apply, logSet, exercise, set, count, grown]", "all_goals rfl",
    ]
  }

  /// The theorem that a defined log keeps the invariants of `Valid`, where the proof counts and searches the sets of a run by their numbers.
  mutating func validity(of name: String, _ log: TrainingLog) throws -> String {
    let summary = "The log keeps the invariants of `Valid`."
    guard let run = definition(of: log)?.run else {
      guard log.sets.count < kernelRows else { throw VectorFault.noProof(name) }
      return theorem(
        "valid_\(name)", summary, ["Valid \(name)"], tactics: ["constructor <;> decide +kernel"])
    }
    guard let owner = log.exercise(run.template.exerciseID) else {
      throw VectorFault.noProof(name)
    }
    return """
      /-- \(summary) -/
      theorem valid_\(name) : Valid \(name) where
        exerciseIDs := by decide +kernel
        exerciseNames := by decide +kernel
        setIDs := by
          simp only [\(name), List.map_map]
          exact List.Pairwise.map _
            (fun (a b : Nat) (different : a ≠ b) => show a + \(run.first) ≠ b + \(run.first) by omega)
            List.nodup_range
        setsNameExercises := by
          intro set member
          simp only [\(name), List.mem_map, List.mem_range] at member
          obtain ⟨i, _, made⟩ := member
          subst made
          exact ⟨\(try exercise(owner)), by decide +kernel, rfl⟩
        exerciseCount := by decide +kernel
        setCount := by
          simp only [\(name), List.length_map, List.length_range]
          decide
        memoDays := by decide +kernel
      """
  }
}

/// The Lean files that hold results of the Swift code, as `mise x -- just gen` writes them.
enum LeanVectors {
  /// The seeds of the random command sequences.
  static let seeds: [UInt64] = [1, 2, 3, 4, 5, 6, 7, 8]
  /// The number of commands that `RandomCommand.next` gives for each seed.
  static let commandsPerSeed = 150

  /// The rows that `TrainingLog.make` reads in one theorem.
  struct Rows {
    let name: String
    let summary: String
    var exercises: [Exercise] = []
    var sets: [LoggedSet] = []
    var memos: [LocalDay: Memo] = [:]

    var made: Result<TrainingLog, IntegrityRefusal> {
      TrainingLog.make(exercises: exercises, sets: sets, memos: memos)
    }

    /// Whether the sets are too many for Lean's kernel to count or search.
    private var huge: Bool { sets.count >= TrainingLog.maximumSets }

    /// The tactics of the theorem, which rewrite the length of a run of a million sets first, because Lean's kernel can't count so many rows.
    var tactics: [String] {
      guard huge else { return ["decide +kernel"] }
      let lemmas =
        ["make", "List.length_replicate"] + (exercises.isEmpty ? ["List.length_nil"] : [])
      return ["simp only [\(lemmas.joined(separator: ", "))]", "decide"]
    }

    /// The theorem that rows keep `Valid` when they form a log, or that they break the invariant of `Valid` that the refusal of `TrainingLog.make` names.
    func validity(_ term: String) throws -> String {
      guard case .failure(let refusal) = made else {
        guard !huge else { throw VectorFault.noProof(name) }
        return theorem(
          "valid_\(name)", "The rows keep the invariants of `Valid`.", ["Valid \(term)"],
          tactics: ["constructor <;> decide +kernel"])
      }
      let field =
        switch refusal {
        case .duplicateExerciseID: "exerciseIDs"
        case .duplicateExerciseName: "exerciseNames"
        case .duplicateSetID: "setIDs"
        case .unknownExercise: "setsNameExercises"
        case .tooManyExercises: "exerciseCount"
        case .tooManySets: "setCount"
        }
      // A million sets are one `List.replicate`, whose length and members the tactics rewrite.
      let repeated = sets.dropFirst().allSatisfy { $0 == sets.first }
      let refutation: [String]
      switch refusal {
      case _ where !huge, .duplicateExerciseID, .duplicateExerciseName, .tooManyExercises:
        refutation = ["exact absurd valid.\(field) (by decide +kernel)"]
      case .tooManySets where repeated:
        refutation = ["exact absurd valid.setCount (by simp only [List.length_replicate]; decide)"]
      case .unknownExercise where repeated && exercises.isEmpty:
        refutation = [
          "obtain ⟨_, member, _⟩ := valid.setsNameExercises _ "
            + "(List.mem_replicate.2 ⟨by decide, rfl⟩)",
          "nomatch member",
        ]
      default:
        throw VectorFault.noProof(name)
      }
      return theorem(
        "invalid_\(name)", "The rows break `\(field)` of `Valid`.", ["¬Valid \(term)"],
        tactics: ["intro valid"] + refutation)
    }
  }

  /// `Gymemo/LogVectors.lean`, with the walks and the row sets that it holds.
  struct LogFile {
    let text: String
    let walks: [Walk]
    let rows: [Rows]
  }

  static func randomCommands(seed: UInt64) -> [Command] {
    var generator = SeededGenerator(seed: seed)
    return (0..<commandsPerSeed).map { _ in RandomCommand.next(using: &generator) }
  }

  /// Commands that the random sequences leave out: each refusal of a text, the widest values, days before 1970, texts that differ only in their bytes, and a replaced log.
  static func handWrittenCommands() throws -> [Command] {
    func add(_ id: UInt32, _ name: String, _ part: BodyPart) -> Command {
      .addExercise(id: exerciseID(id), name: name, bodyPart: part)
    }
    func edit(_ id: UInt32, _ name: String, _ part: BodyPart) -> Command {
      .editExercise(id: exerciseID(id), name: name, bodyPart: part)
    }
    func archive(_ id: UInt32, _ isArchived: Bool) -> Command {
      .setExerciseArchived(id: exerciseID(id), isArchived: isArchived)
    }
    func logSet(
      _ id: UInt32, _ exercise: UInt32, _ day: LocalDay, _ weight: String, _ count: Int
    ) throws -> Command {
      .logSet(
        id: setID(id), exerciseID: exerciseID(exercise), day: day, weight: try kilograms(weight),
        reps: try reps(count))
    }
    func editSet(_ id: UInt32, _ weight: String, _ count: Int) throws -> Command {
      .editSet(id: setID(id), weight: try kilograms(weight), reps: try reps(count))
    }
    let first = LocalDay.earliest
    let eve = try day("1969-12-31")
    let epoch = try day("1970-01-01")
    let monday = try day("2026-11-09")
    let last = LocalDay.latest
    let longest = String(repeating: "あ", count: ExerciseName.maximumLength)
    let replacement = try TrainingLog.empty.applying(
      add(7, "懸垂", .back), add(8, "デッドリフト", .legs), archive(8, true),
      logSet(8, 7, eve, "0", 12), logSet(9, 8, monday, "140", 5),
      .writeMemo(day: eve, text: "肩が重い"), .writeMemo(day: monday, text: "新しい記録"))
    return try [
      // The empty log replaces a log with rows, and a log with rows replaces the empty log, twice without a shortcut.
      add(5, "プランク", .abdominals),
      logSet(5, 5, monday, "0", 30),
      .writeMemo(day: epoch, text: "古い記録"),
      .replaceAll(.empty),
      .deleteSet(id: setID(5)),
      .deleteExercise(id: exerciseID(5)),
      .writeMemo(day: epoch, text: ""),
      .replaceAll(replacement),
      .replaceAll(replacement),
      logSet(2, 7, monday, "20", 5),
      logSet(8, 7, monday, "20", 5),
      logSet(3, 5, monday, "20", 5),
      .deleteSet(id: setID(8)),
      edit(7, "デッドリフト", .back),
      archive(8, false),
      // Exercises, where the log refuses a text before its identifier and an identifier before its name.
      add(1, " ベンチプレス ", .chest),
      add(2, "スクワット", .legs),
      add(2, "懸垂", .back),
      add(3, "ベンチプレス\n", .arms),
      add(1, "", .other),
      add(3, longest + "あ", .other),
      edit(3, longest + "あ", .other),
      add(3, "ベンチ\tプレス", .other),
      add(3, longest, .abdominals),
      add(4, "カ\u{3099}", .shoulders),
      edit(3, "ガ", .abdominals),
      edit(4, "ガ", .shoulders),
      edit(4, "ガ", .arms),
      edit(4, "プランク", .abdominals),
      edit(9, "ガ", .other),
      edit(9, " ", .other),
      archive(2, true),
      archive(2, true),
      archive(2, false),
      archive(9, true),
      // Sets, with the first and the last supported day and the lightest and the heaviest load.
      logSet(1, 1, monday, "60", 10),
      logSet(1, 2, monday, "0", 1),
      logSet(1, 9, monday, "0", 1),
      logSet(3, 1, first, "999.99", 999),
      logSet(4, 2, last, "0.01", 1),
      logSet(5, 2, eve, "0", 12),
      editSet(1, "62.5", 8),
      editSet(1, "62.5", 8),
      editSet(1, "62.5", 9),
      editSet(6, "0", 1),
      .deleteExercise(id: exerciseID(1)),
      .deleteExercise(id: exerciseID(9)),
      .deleteSet(id: setID(6)),
      .deleteSet(id: setID(1)),
      .deleteSet(id: setID(3)),
      .deleteExercise(id: exerciseID(1)),
      add(1, "ベンチプレス", .chest),
      logSet(1, 1, monday, "60", 10),
      // Memos before, between, and after the others, and one that replaces the memo of the replaced log.
      // Then texts that `Memo.parse` makes equal to the memo of their day, and one that a blank text removes.
      .writeMemo(day: first, text: "一行目\r\n二行目"),
      .writeMemo(day: epoch, text: "カ\u{3099}"),
      .writeMemo(day: last, text: " 肩が重い\n"),
      .writeMemo(day: first, text: "一行目\n二行目"),
      .writeMemo(day: epoch, text: "ガ"),
      .writeMemo(day: monday, text: "腰は軽い"),
      .writeMemo(day: eve, text: " \n"),
      .writeMemo(day: eve, text: ""),
      .writeMemo(day: monday, text: "a\u{0}b"),
      .writeMemo(day: monday, text: String(repeating: "あ", count: Memo.maximumLength + 1)),
    ]
  }

  /// A log of one exercise fewer than the limit.
  static func nearlyFullLog() throws -> TrainingLog {
    let exercises = try (1..<TrainingLog.maximumExercises).map { number in
      Exercise(
        id: exerciseID(UInt32(1000 + number)), name: try ExerciseName.parse("種目\(number)").get(),
        bodyPart: .other)
    }
    return try TrainingLog.make(exercises: exercises, sets: [], memos: [:]).get()
  }

  /// Commands that fill a log to the exercise limit and refuse one more exercise as `.full`.
  static func exerciseLimitCommands(from nearlyFull: TrainingLog) -> [Command] {
    func add(_ id: UInt32, _ name: String) -> Command {
      .addExercise(id: exerciseID(id), name: name, bodyPart: .chest)
    }
    return [
      .replaceAll(nearlyFull),
      add(2000, "種目1000"),
      // A full log refuses a repeated identifier or name for that reason, and only then a new exercise.
      add(1001, "種目1001"),
      add(2001, "種目1"),
      add(2001, "種目1001"),
      .deleteExercise(id: exerciseID(2000)),
      add(2001, "種目1001"),
      // `make` over a full log ran out of the memory of the proof run, so a small log replaces it before the end.
      .replaceAll(.empty),
      add(1, "ベンチプレス"),
    ]
  }

  /// A log of one exercise and one set fewer than the limit, whose set identifiers count up from one.
  static func nearlyFullOfSets() throws -> TrainingLog {
    let bench = Exercise(
      id: exerciseID(1), name: try ExerciseName.parse("ベンチプレス").get(), bodyPart: .chest)
    let monday = try day("2026-11-09")
    let load = try kilograms("60")
    let sets = (1..<TrainingLog.maximumSets).map { number in
      LoggedSet(
        id: setID(UInt32(number)), exerciseID: bench.id, day: monday, weight: load, reps: .one)
    }
    return try TrainingLog.make(exercises: [bench], sets: sets, memos: [:]).get()
  }

  /// Commands that fill a log to the set limit and refuse one more set as `.full`.
  /// The full log still refuses a set of no exercise and a repeated identifier for those reasons.
  static func setLimitCommands(from nearlyFull: TrainingLog) throws -> [Command] {
    let monday = try day("2026-11-09")
    let load = try kilograms("60")
    func logSet(_ id: Int, _ exercise: UInt32) -> Command {
      .logSet(
        id: setID(UInt32(id)), exerciseID: exerciseID(exercise), day: monday, weight: load,
        reps: .one)
    }
    let next = TrainingLog.maximumSets + 1
    return [
      .replaceAll(nearlyFull), logSet(TrainingLog.maximumSets, 1), logSet(next, 1),
      logSet(next, 9), logSet(1, 1),
    ]
  }

  /// Rows for each refusal that `TrainingLog.make` gives, and rows that form a log.
  static func rowSets() throws -> [Rows] {
    func name(_ text: String) throws -> ExerciseName { try ExerciseName.parse(text).get() }
    func set(_ id: UInt32, _ exercise: UInt32, _ day: LocalDay) throws -> LoggedSet {
      LoggedSet(
        id: setID(id), exerciseID: exerciseID(exercise), day: day, weight: try kilograms("60"),
        reps: try reps(10))
    }
    let monday = try day("2026-11-09")
    let eve = try day("1969-12-31")
    let bench = Exercise(id: exerciseID(1), name: try name("ベンチプレス"), bodyPart: .chest)
    let squat = Exercise(
      id: exerciseID(2), name: try name("スクワット"), bodyPart: .legs, isArchived: true)
    let renamed = Exercise(id: exerciseID(1), name: try name("デッドリフト"), bodyPart: .back)
    let twin = Exercise(id: exerciseID(3), name: bench.name, bodyPart: .other)
    let memo = try Memo.parse("肩が重い").get()
    return [
      Rows(
        name: "wholeRows", summary: "Rows that keep every invariant form a log.",
        exercises: [bench, squat], sets: [try set(1, 1, monday), try set(2, 2, eve)],
        memos: memo.map { [monday: $0] } ?? [:]),
      Rows(
        name: "repeatedExerciseIdentifier", summary: "Two exercises bear one identifier.",
        exercises: [bench, squat, renamed]),
      Rows(
        name: "repeatedExerciseName", summary: "Two exercises bear one name.",
        exercises: [bench, squat, twin]),
      Rows(
        name: "repeatedExercise",
        summary: "An exercise that repeats an identifier and a name is refused for its identifier.",
        exercises: [bench, bench]),
      Rows(
        name: "repeatedSetIdentifier", summary: "Two sets bear one identifier.",
        exercises: [bench, squat],
        sets: [try set(1, 1, monday), try set(2, 2, eve), try set(1, 2, monday)]),
      Rows(
        name: "setOfNoExercise", summary: "A set names an exercise that the rows don't hold.",
        exercises: [bench], sets: [try set(1, 1, monday), try set(2, 2, eve)]),
      Rows(
        name: "repeatedSetOfNoExercise",
        summary:
          "A set that repeats an identifier and names no exercise is refused for its identifier.",
        exercises: [bench], sets: [try set(1, 1, monday), try set(1, 9, monday)]),
      Rows(
        name: "strayThenRepeatedSet",
        summary: "The first set that breaks the rows decides the refusal.",
        exercises: [bench], sets: [try set(1, 9, monday), try set(1, 1, monday)]),
      Rows(
        name: "brokenExercisesAndSets", summary: "The exercises are read before the sets.",
        exercises: [bench, twin], sets: [try set(1, 9, monday)]),
      Rows(
        name: "exercisesAtTheLimit",
        summary: "A thousand exercises pass the limit, so their first repeated row decides.",
        exercises: Array(repeating: bench, count: TrainingLog.maximumExercises)),
      Rows(
        name: "exercisesBeyondTheLimit",
        summary: "One exercise more than a thousand is refused before any row is read.",
        exercises: Array(repeating: bench, count: TrainingLog.maximumExercises + 1)),
      Rows(
        name: "setsAtTheLimit",
        summary:
          "A million sets pass the limit, so their first set, which names no exercise, decides.",
        sets: Array(repeating: try set(1, 1, monday), count: TrainingLog.maximumSets)),
      Rows(
        name: "setsBeyondTheLimit",
        summary: "One set more than a million is refused before any row is read.",
        sets: Array(repeating: try set(1, 1, monday), count: TrainingLog.maximumSets + 1)),
      Rows(
        name: "beyondBothLimits",
        summary: "Rows beyond both limits are refused for their exercises.",
        exercises: Array(repeating: bench, count: TrainingLog.maximumExercises + 1),
        sets: Array(repeating: try set(1, 1, monday), count: TrainingLog.maximumSets + 1)),
    ]
  }

  /// The definitions and the theorems of one command sequence, after the logs that its commands name.
  private static func section(
    _ walk: Walk, name: String, title: String, logs: [(name: String, log: TrainingLog)] = [],
    terms: inout LogTerms
  ) throws -> String {
    let definitions = try logs.map { try terms.define($0.name, $0.log) }
    let commands = try walk.commands.map { try terms.command($0) }
    let steps = try walk.results.map { try terms.step($0) }
    let refused = walk.commands.count - walk.accepted
    let last = walk.final
    let made = TrainingLog.make(exercises: last.exercises, sets: last.sets, memos: last.memos)
    let header =
      "/-! ## \(title): \(walk.commands.count) commands, of which the log accepted "
      + "\(walk.accepted) and refused \(refused) -/"
    return
      ([header] + definitions + [
        "def \(name)Commands : List Command := \(tall(commands))",
        "def \(name)Steps : List Step := \(tall(steps))",
        "def \(name)Final : Log := \(try terms.spread(last))",
        theorem(
          "outcomes_\(name)", "The model gives each step and the last log of the Swift code.",
          ["outcomes Log.empty \(name)Commands = (\(name)Steps, \(name)Final)"]),
        theorem(
          "stored_\(name)",
          "A store that receives the changes of each accepted command holds the last log of the Swift code.",
          ["stored Log.empty Log.empty \(name)Commands = \(name)Final"]),
        theorem(
          "applied_\(name)",
          "The log of `applied` after the commands is the last log of the Swift code.",
          ["applied Log.empty \(name)Commands = \(name)Final"]),
        theorem(
          "make_\(name)Final",
          "The model reads the rows of the last log as `TrainingLog.make` does.",
          ["make \(name)Final = \(terms.made(made))"]),
        try terms.validity(of: "\(name)Final", last),
      ]).joined(separator: "\n\n")
  }

  /// The definitions and the theorems of a command sequence over logs too long for Lean's kernel to compare.
  /// A theorem for each command stands in place of the theorems of a whole sequence.
  private static func transitions(
    _ walk: Walk, name: String, title: String, logs: [(name: String, log: TrainingLog)],
    terms: inout LogTerms
  ) throws -> String {
    // A log that a command gives beyond the given ones, as a changed Swift code can, gets a definition too, so that Lean still checks the theorem of that command.
    var logs = logs
    for (position, result) in walk.results.enumerated() {
      guard case .success(let transition) = result, transition.log.sets.count >= kernelRows,
        !logs.contains(where: { sameRows($0.log, transition.log) })
      else { continue }
      logs.append(("\(name)After\(position)", transition.log))
    }
    var declarations = try logs.map { try terms.define($0.name, $0.log) }
    for (name, log) in logs {
      declarations.append(try terms.validity(of: name, log))
    }
    for (position, command) in walk.commands.enumerated() {
      let log = walk.logs[position]
      let result = walk.results[position]
      let line =
        "apply \(try terms.log(log)) (\(try terms.command(command))) =\n      "
        + (try terms.outcome(result))
      declarations.append(
        theorem(
          "apply_\(name)_\(position)",
          "The model gives the result of the Swift code for command \(position), counted from zero.",
          [line], tactics: try terms.tactics(log, command, result)))
    }
    let header =
      "/-! ## \(title): \(walk.commands.count) commands, of which the log accepted "
      + "\(walk.accepted) and refused \(walk.commands.count - walk.accepted) -/"
    return ([header] + declarations).joined(separator: "\n\n")
  }

  static func log() throws -> LogFile {
    var terms = LogTerms()
    let limits = [
      "maximumExercises = \(TrainingLog.maximumExercises)",
      "maximumSets = \(TrainingLog.maximumSets)",
    ]
    var declarations = [theorem("limits", "The limits of `TrainingLog`.", limits)]
    var walks: [Walk] = []
    for seed in seeds {
      let walk = Walk(randomCommands(seed: seed))
      let title = "Seed \(seed) of `RandomCommand.next`"
      declarations.append(try section(walk, name: "seed\(seed)", title: title, terms: &terms))
      walks.append(walk)
    }
    let handWritten = Walk(try handWrittenCommands())
    let title = "A hand-written sequence"
    declarations.append(try section(handWritten, name: "handWritten", title: title, terms: &terms))
    walks.append(handWritten)
    let nearlyFull = try nearlyFullLog()
    let limit = Walk(exerciseLimitCommands(from: nearlyFull))
    declarations.append(
      try section(
        limit, name: "exerciseLimit", title: "The exercise limit",
        logs: [("nearlyFullLog", nearlyFull)], terms: &terms))
    walks.append(limit)
    let oneSetShort = try nearlyFullOfSets()
    let filled = Walk(try setLimitCommands(from: oneSetShort))
    // The second command logs the last set, so the log that the third command meets is the full one.
    declarations.append(
      try transitions(
        filled, name: "setLimit", title: "The set limit",
        logs: [("nearlyFullOfSets", oneSetShort), ("fullOfSets", filled.logs[2])],
        terms: &terms))
    walks.append(filled)
    let rowSets = try rowSets()
    declarations.append("/-! ## Rows that `TrainingLog.make` reads -/")
    for rows in rowSets {
      let term = try terms.rows(exercises: rows.exercises, sets: rows.sets, memos: rows.memos)
      let line = "make \(term) =\n      \(terms.made(rows.made))"
      declarations.append(
        theorem("make_\(rows.name)", rows.summary, [line], tactics: rows.tactics))
      declarations.append(try rows.validity(term))
    }
    let notes = """
      Each theorem holds when the model of `Gymemo/Log.lean` gives the result of the Swift code, \
      and Lean's kernel computes the model's result after the rewrites that the notes below name.
      When the theorem of a sequence fails, `#eval ((outcomes Log.empty seed1Commands).1.zip \
      seed1Steps).findIdx? (fun (model, swift) => model != swift)` gives the place of the first \
      step that differs, counted from zero.

      An exercise or a set bears the number in the last four bytes of its UUID.
      A day is its `LocalDay.dayNumber`, a weight counts hundredths of a kilogram, \
      and the memos of a log lie in the order of their days.
      A run of sets whose identifiers count up by one and whose other fields agree is \
      `(List.range n).map`, and a run of one repeated row is `List.replicate`.
      A name or a memo text is a number of the tables below, in the order of first use.
      A command holds `.refused` for a text that `ExerciseName.parse` or `Memo.parse` refuses, \
      and `.nothing` for a memo text that holds nothing to keep.

      Each sequence other than the set limit also holds the rows of a store that receives the \
      changes of each accepted command, the log of `applied`, and `Valid` for its last log.

      The sequence of the exercise limit fills a log to a thousand exercises and refuses one more \
      as `.full`.
      It replaces the full log before its end, because `make` over a thousand distinct exercises \
      ran out of the memory of the proof run.

      The sequence of the set limit fills a log to a million sets and refuses one more as `.full`, \
      while the full log still refuses a set of no exercise and a repeated identifier for those \
      reasons.
      Lean's kernel can't compare or search a million sets, so that sequence holds a theorem for \
      each command and `Valid` for each of its logs in place of the theorems of a whole sequence.
      Those theorems rewrite the search and the count of the sets before they decide.

      Rows that `TrainingLog.make` refuses break the invariant of `Valid` that the refusal names, \
      and rows that form a log keep `Valid`.
      The theorems over a million rows rewrite the length of `List.replicate` before they decide, \
      because Lean's kernel can't count so many rows.
      """
    let text = file(
      module: "Gymemo.Log", title: "Results of the Swift code for the rules of the log",
      origin: "`TrainingLog.apply` and `TrainingLog.make` return", notes: notes,
      tables: [
        table("The names by their numbers.", terms.names.values.map(\.text)),
        table("The memo texts by their numbers.", terms.memos.values.map(\.text)),
      ], declarations: declarations)
    return LogFile(text: text, walks: walks, rows: rowSets)
  }

  /// The weights of the estimates in hundredths of a kilogram, from the lightest to the heaviest.
  /// With the counts below, 0.05 kg once lands on half of a tenth.
  /// 0.04 kg for 8 lands 2/3000 kg over such a half, and 0.77 kg for 7 lands 1/3000 kg under one.
  static let estimateWeights = [1, 4, 5, 77, 250, 6000, 6250, 99_999]
  /// The repetition counts of the estimates.
  static let estimateCounts = [1, 2, 5, 7, 8, 10, 30, 999]

  /// `Gymemo/StrengthVectors.lean`.
  static func strength() throws -> String {
    let limits = [
      "maximumHundredths = \(Weight.maximumHundredths)", "maximumCount = \(Reps.maximumCount)",
    ]
    var theorems = [theorem("limits", "The limits of `Weight` and `Reps`.", limits)]
    for hundredths in estimateWeights {
      guard let weight = Weight(hundredths: hundredths) else {
        throw VectorFault.outOfRange(hundredths)
      }
      let lines = try estimateCounts.map { count in
        guard let reps = Reps(count) else { throw VectorFault.outOfRange(count) }
        guard let estimate = OneRepMax.estimate(weight: weight, reps: reps) else {
          throw VectorFault.noEstimate(hundredths: hundredths)
        }
        return "tenths (units \(hundredths) \(count)) = \(estimate.tenths)"
      }
      let summary = "The estimates of \(weight.text) kg."
      theorems.append(theorem("tenths_units_\(hundredths)", summary, lines))
    }
    let notes = """
      Each line holds when `tenths (units weight reps)` of `Gymemo/Strength.lean` gives the \
      `tenths` of the Swift estimate for a weight in hundredths of a kilogram.
      A set without added weight has no estimate in the Swift code, \
      so no line starts from a weight of zero.
      """
    return file(
      module: "Gymemo.Strength",
      title: "Results of the Swift code for the estimated one-repetition load",
      origin: "`OneRepMax.estimate` returns", notes: notes, declarations: theorems)
  }

  /// The step counts of the steppers, from the least to the greatest 64-bit integer, with the counts beside each edge of a range.
  static let stepCounts = [
    Int.min, -100_000, -1000, -999, -998, -400, -399, -1, 0, 1, 399, 400, 998, 999, 1000, 100_000,
    Int.max,
  ]
  /// The weights that a stepper starts from in hundredths of a kilogram, after the empty field.
  static let steppedWeights = [0, 1, 250, 6000, 6250, 99_999]
  /// The repetition counts that a stepper starts from, after the empty field.
  static let steppedCounts = [1, 2, 5, 8, 30, 999]

  /// `Gymemo/StepperVectors.lean`.
  static func stepper() throws -> String {
    let constants = [
      "maximumHundredths = \(Weight.maximumHundredths)",
      "stepHundredths = \(Weight.stepHundredths)", "maximumCount = \(Reps.maximumCount)",
    ]
    var theorems = [
      theorem("constants", "The limits and the weight step of the Swift code.", constants)
    ]
    for start in [nil] + steppedWeights.map(Optional.some) {
      var text = ""
      if let start {
        guard let weight = Weight(hundredths: start) else { throw VectorFault.outOfRange(start) }
        text = weight.text
      }
      let lines = try stepCounts.map { steps in
        guard let stepped = Weight.stepped(from: text, by: steps) else {
          throw VectorFault.noStep(from: text, by: steps)
        }
        return "weightStepped \(start ?? 0) \(integer(steps)) = \(stepped.hundredths)"
      }
      let name = "weightStepped_from\(start.map { "\($0)" } ?? "Empty")"
      let summary =
        start == nil ? "The weight field is empty." : "The weight field holds `\(text)`."
      theorems.append(theorem(name, summary, lines))
    }
    for start in [nil] + steppedCounts.map(Optional.some) {
      let text = start.map { "\($0)" } ?? ""
      var lines: [String] = []
      for steps in stepCounts {
        guard let stepped = Reps.stepped(from: text, by: steps) else {
          // An empty field that steps down or stays gives no count, and the model starts where a count exists.
          if start == nil && steps <= 0 { continue }
          throw VectorFault.noStep(from: text, by: steps)
        }
        lines.append("repsStepped \(start ?? 0) \(integer(steps)) = \(stepped.count)")
      }
      let name = "repsStepped_from\(start.map { "\($0)" } ?? "Empty")"
      let summary =
        start == nil ? "The repetitions field is empty." : "The repetitions field holds `\(text)`."
      theorems.append(theorem(name, summary, lines))
    }
    let notes = """
      Each line holds when `weightStepped` or `repsStepped` of `Gymemo/Stepper.lean` gives the \
      result of the Swift code from the same start by the same step count.
      An empty weight field starts at zero.
      An empty repetitions field starts at zero when it steps up, and the Swift code gives no \
      count when it steps down or stays, so no line holds such a pair.
      The first and the last step count of each theorem are the least and the greatest 64-bit integer.
      """
    return file(
      module: "Gymemo.Stepper", title: "Results of the Swift code for the steppers",
      origin: "`Weight.stepped` and `Reps.stepped` return for the text of a field", notes: notes,
      declarations: theorems)
  }
}
