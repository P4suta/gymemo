import GymemoCopy
import GymemoCore
import SwiftUI

/// One day's sets and note, for today in the Log tab and for any other day from History.
struct DayScreen: View {
  let day: LocalDay
  @Environment(AppModel.self) private var model
  @State private var pending: [ExerciseID] = []
  @State private var isPickingExercise = false
  @State private var isEditingNote = false
  @State private var editedSet: LoggedSet?

  private struct Shown: Identifiable {
    let exercise: Exercise
    let sets: [LoggedSet]

    var id: ExerciseID { exercise.id }
  }

  private var shown: [Shown] {
    let logged = model.log.sections(on: day).map { Shown(exercise: $0.exercise, sets: $0.sets) }
    let waiting = pending.filter { id in !logged.contains { $0.id == id } }
      .compactMap { model.log.exercise($0) }
      .map { Shown(exercise: $0, sets: []) }
    return logged + waiting
  }

  var body: some View {
    let sections = shown
    let bests = model.log.personalBests(on: day)
    let isToday = day == model.today
    let note = model.log.memo(on: day)
    List {
      if !isToday {
        Section {
          Label(copy[.dayNotToday], systemImage: "calendar")
        }
      }
      if sections.isEmpty {
        Section {
          ContentUnavailableView {
            Label(copy[.dayEmptyTitle], systemImage: "dumbbell")
          } description: {
            Text(copy[.dayEmpty])
          } actions: {
            Button(copy[.addExercise]) { isPickingExercise = true }
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("add-first-exercise")
          }
          .accessibilityIdentifier("empty-day")
        }
        .listRowBackground(Color.clear)
      }
      ForEach(sections) { section in
        ExerciseSection(
          exercise: section.exercise, sets: section.sets, day: day, bests: bests,
          previous: model.log.previousSession(of: section.exercise.id, before: day),
          suggestion: model.log.suggestedEntry(for: section.exercise.id, on: day)
        ) { editedSet = $0 }
      }
      Section(copy[.note]) {
        if let note {
          Text(note.text).accessibilityIdentifier("note-text")
        }
        Button(note == nil ? copy[.writeNote] : copy[.editNote], systemImage: "square.and.pencil") {
          isEditingNote = true
        }
        .accessibilityIdentifier("edit-note")
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle(isToday ? copy[.tabLog] : copy.day(day, .long))
    .navigationSubtitle(isToday ? copy.day(day, .long) : "")
    .toolbarTitleDisplayMode(isToday ? .large : .inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(copy[.addExercise], systemImage: "plus") { isPickingExercise = true }
          .accessibilityIdentifier("add-exercise")
      }
    }
    .keyboardDismissal()
    .sheet(isPresented: $isPickingExercise) {
      ExercisePicker { exercise in
        if !pending.contains(exercise.id) { pending.append(exercise.id) }
      }
    }
    .sheet(isPresented: $isEditingNote) {
      NoteEditor(day: day, text: note?.text ?? "")
    }
    .sheet(item: $editedSet) { set in
      SetEditor(set: set)
    }
  }
}

/// One exercise of a day: the previous session, each logged set, and the rows that log the next set.
private struct ExerciseSection: View {
  let exercise: Exercise
  let sets: [LoggedSet]
  let day: LocalDay
  let bests: Set<SetID>
  let previous: Session?
  let suggestion: SetEntry?
  let edit: (LoggedSet) -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    let name = exercise.name.text
    Section {
      if let previous {
        Text(copy.previous(previous))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("previous-session-\(name)")
      }
      ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
        let isBest = bests.contains(set.id)
        Button {
          edit(set)
        } label: {
          SetRow(number: index + 1, set: set, isBest: isBest)
        }
        .tint(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          copy.spokenSet(weight: set.weight, reps: set.reps, number: index + 1, isBest: isBest)
        )
        .accessibilityHint(copy[.setEditHint])
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("set-\(index + 1)-\(name)")
        .swipeActions(edge: .trailing) {
          Button(copy[.delete], systemImage: "trash", role: .destructive) {
            model.perform(.deleteSet(id: set.id))
          }
          Button(copy[.edit], systemImage: "pencil") { edit(set) }
        }
        .contextMenu {
          Button(copy[.edit], systemImage: "pencil") { edit(set) }
          Button(copy[.delete], systemImage: "trash", role: .destructive) {
            model.perform(.deleteSet(id: set.id))
          }
        }
      }
      SetEntryRows(exercise: exercise, day: day, suggestion: suggestion)
    } header: {
      Text(name)
    }
    .headerProminence(.increased)
  }
}

/// The weight, the repetitions, and the button of the next set, already filled with the suggested values.
/// The fields keep the set that was just logged, so one more tap logs the same set again.
private struct SetEntryRows: View {
  let exercise: Exercise
  let day: LocalDay
  @Environment(AppModel.self) private var model
  @State private var weightText: String
  @State private var repsText: String
  @State private var problem: String?
  @State private var logged = 0
  @State private var refused = 0

  init(exercise: Exercise, day: LocalDay, suggestion: SetEntry?) {
    self.exercise = exercise
    self.day = day
    _weightText = State(initialValue: suggestion.map { copy.weightField($0.weight) } ?? "")
    _repsText = State(initialValue: suggestion.map { "\($0.reps.count)" } ?? "")
  }

  var body: some View {
    let name = exercise.name.text
    NumberFieldRow(kind: .weight, text: $weightText, identifier: "weight-\(name)")
    NumberFieldRow(kind: .reps, text: $repsText, identifier: "reps-\(name)")
    if let problem { InlineProblem(text: problem, identifier: "problem-\(name)") }
    Button(copy[.logSet], systemImage: "plus.circle.fill", action: record)
      .accessibilityIdentifier("log-set-\(name)")
      .sensoryFeedback(.success, trigger: logged)
      .sensoryFeedback(.error, trigger: refused)
  }

  private func record() {
    switch SetEntry.parse(weight: weightText, reps: repsText) {
    case .failure(let refusal):
      problem = copy.problem(entry: refusal)
      refused += 1
    case .success(let entry):
      let command = Command.logSet(
        id: model.newSetID(), exerciseID: exercise.id, day: day, weight: entry.weight,
        reps: entry.reps)
      if model.perform(command) == .done {
        problem = nil
        logged += 1
      }
    }
  }
}

/// Changes or deletes one logged set.
struct SetEditor: View {
  let set: LoggedSet
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var weightText: String
  @State private var repsText: String
  @State private var problem: String?
  private let initialWeight: String
  private let initialReps: String

  init(set: LoggedSet) {
    self.set = set
    initialWeight = copy.weightField(set.weight)
    initialReps = "\(set.reps.count)"
    _weightText = State(initialValue: initialWeight)
    _repsText = State(initialValue: initialReps)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          NumberFieldRow(kind: .weight, text: $weightText, identifier: "edit-weight")
          NumberFieldRow(kind: .reps, text: $repsText, identifier: "edit-reps")
          if let problem { InlineProblem(text: problem) }
        } header: {
          if let exercise = model.log.exercise(set.exerciseID) { Text(exercise.name.text) }
        }
        Section {
          Button(copy[.deleteSet], role: .destructive) {
            if model.perform(.deleteSet(id: set.id)) != .notStored { dismiss() }
          }
          .accessibilityIdentifier("delete-set")
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .keyboardDismissal()
      .sheetToolbar(
        title: copy[.editSet], confirmTitle: copy[.save],
        isDirty: weightText != initialWeight || repsText != initialReps, confirm: save)
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func save() {
    switch SetEntry.parse(weight: weightText, reps: repsText) {
    case .failure(let refusal):
      problem = copy.problem(entry: refusal)
    case .success(let entry):
      let command = Command.editSet(id: set.id, weight: entry.weight, reps: entry.reps)
      if model.perform(command) != .notStored { dismiss() }
    }
  }
}

/// Writes, changes, or clears the note of one day.
struct NoteEditor: View {
  let day: LocalDay
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var text: String
  @State private var problem: String?
  private let initialText: String

  init(day: LocalDay, text: String) {
    self.day = day
    initialText = text
    _text = State(initialValue: text)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextEditor(text: $text)
            .frame(minHeight: 180)
            .accessibilityLabel(copy[.note])
            .accessibilityIdentifier("note-editor")
          if let problem { InlineProblem(text: problem) }
        } footer: {
          Text(copy[.noteHint])
        }
      }
      .navigationSubtitle(copy.day(day, .long))
      .sheetToolbar(
        title: copy[.note], confirmTitle: copy[.save], isDirty: text != initialText, confirm: save)
    }
  }

  private func save() {
    switch model.perform(.writeMemo(day: day, text: text)) {
    case .done: dismiss()
    case .refused(let refusal): problem = copy.problem(note: refusal)
    case .notStored: break
    }
  }
}
