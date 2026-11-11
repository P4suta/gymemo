public struct CompanionQueuedSet: Equatable, Identifiable, Sendable {
  public let set: LoggedSet
  public let outcome: CompanionOutcome?
  public let exerciseName: ExerciseName?
  public var id: SetID { self.set.id }

  public init(set: LoggedSet, outcome: CompanionOutcome?, exerciseName: ExerciseName? = nil) {
    self.set = set
    self.outcome = outcome
    self.exerciseName = exerciseName
  }
}

public enum CompanionQueueRefusal: Error, Equatable, Sendable {
  case duplicateIdentifier, full
}

public struct CompanionQueue: Equatable, Sendable {
  public static let maximumEntries = 1_000
  public let entries: [CompanionQueuedSet]

  public init() { entries = [] }

  public init?(entries: [CompanionQueuedSet]) {
    guard entries.count <= Self.maximumEntries,
      Set(entries.map(\.id)).count == entries.count
    else { return nil }
    self.entries = entries
  }

  private init(checked entries: [CompanionQueuedSet]) { self.entries = entries }

  public func enqueue(_ set: LoggedSet, name: ExerciseName?) -> Result<Self, CompanionQueueRefusal>
  {
    guard !entries.contains(where: { $0.id == set.id }) else {
      return .failure(.duplicateIdentifier)
    }
    let saved = Set(entries.filter { $0.outcome == .saved }.suffix(99).map(\.id))
    let retained = entries.filter { $0.outcome != .saved || saved.contains($0.id) }
    guard retained.count < Self.maximumEntries else { return .failure(.full) }
    return .success(
      Self(checked: retained + [CompanionQueuedSet(set: set, outcome: nil, exerciseName: name)]))
  }

  public func acknowledging(_ receipt: CompanionReceipt) -> Self {
    guard let index = entries.firstIndex(where: { $0.set == receipt.set }),
      entries[index].outcome != .saved
    else { return self }
    var changed = entries
    changed[index] = CompanionQueuedSet(
      set: receipt.set, outcome: receipt.outcome, exerciseName: entries[index].exerciseName)
    return Self(checked: changed)
  }

  public func retrying(_ id: SetID) -> Self {
    guard let index = entries.firstIndex(where: { $0.id == id }),
      entries[index].outcome != .saved
    else { return self }
    var changed = entries
    changed[index] = CompanionQueuedSet(
      set: changed[index].set, outcome: nil, exerciseName: changed[index].exerciseName)
    return Self(checked: changed)
  }
}
