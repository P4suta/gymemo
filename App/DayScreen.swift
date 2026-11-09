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
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if day != model.today {
          Label(copy[.dayNotToday], systemImage: "calendar")
            .font(.subheadline.weight(.semibold))
        }
        NoteBlock(note: model.log.memo(on: day)) { isEditingNote = true }
        if sections.isEmpty {
          Text(copy[.dayEmpty]).accessibilityIdentifier("empty-day")
        }
        ForEach(sections) { section in
          Rule()
          ExerciseBlock(
            exercise: section.exercise, sets: section.sets, day: day, bests: bests,
            previous: model.log.previousSession(of: section.exercise.id, before: day),
            suggestion: model.log.suggestedEntry(for: section.exercise.id, on: day)
          ) { editedSet = $0 }
        }
        Rule()
        Button {
          isPickingExercise = true
        } label: {
          Label(copy[.addExercise], systemImage: "plus")
        }
        .buttonStyle(MonoButtonStyle(prominent: sections.isEmpty))
        .accessibilityIdentifier("add-exercise")
      }
      .padding(16)
    }
    .scrollDismissesKeyboard(.interactively)
    .screenSurface()
    .navigationTitle(copy.day(day, .long))
    .navigationBarTitleDisplayMode(.inline)
    .keyboardDismissal()
    .sheet(isPresented: $isPickingExercise) {
      ExercisePicker { exercise in
        if !pending.contains(exercise.id) { pending.append(exercise.id) }
      }
    }
    .sheet(isPresented: $isEditingNote) {
      NoteEditor(day: day, text: model.log.memo(on: day)?.text ?? "")
    }
    .sheet(item: $editedSet) { set in
      SetEditor(set: set)
    }
  }
}

private struct NoteBlock: View {
  let note: Memo?
  let edit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let note {
        GroupHeading(text: copy[.note], icon: "note.text")
        Text(note.text).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("note-text")
      }
      Button(action: edit) {
        Label(note == nil ? copy[.writeNote] : copy[.editNote], systemImage: "square.and.pencil")
      }
      .buttonStyle(MonoButtonStyle())
      .accessibilityIdentifier("edit-note")
    }
  }
}

private struct ExerciseBlock: View {
  let exercise: Exercise
  let sets: [LoggedSet]
  let day: LocalDay
  let bests: Set<SetID>
  let previous: Session?
  let suggestion: SetEntry?
  let edit: (LoggedSet) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      GroupHeading(text: exercise.name.text, icon: "dumbbell").font(.title3.bold())
      if let previous {
        Text(copy.previous(previous))
          .font(.subheadline)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("previous-session")
      }
      VStack(spacing: 0) {
        ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
          SetRow(number: index + 1, set: set, isBest: bests.contains(set.id)) { edit(set) }
        }
      }
      SetEntryRow(exercise: exercise, day: day, suggestion: suggestion)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("exercise-\(exercise.name.text)")
  }
}

private struct SetRow: View {
  let number: Int
  let set: LoggedSet
  let isBest: Bool
  let edit: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    RowButton(action: edit) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(number.formatted(.number.locale(copy.locale)))
          .font(.body.monospacedDigit())
          .frame(minWidth: 24, alignment: .leading)
        // At the accessibility sizes the badge moves below the set, so neither wraps inside a narrow column.
        let layout =
          typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
          : AnyLayout(HStackLayout(spacing: 12))
        layout {
          Text(copy.set(set)).font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
          if isBest { Badge(text: copy[.personalBest], icon: "trophy") }
        }
        Spacer(minLength: 8)
        Image(systemName: "pencil")
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      copy.spokenSet(weight: set.weight, reps: set.reps, number: number, isBest: isBest)
    )
    .accessibilityHint(copy[.setEditHint])
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("set-\(number)")
  }
}

/// The weight and repetitions of the next set, already filled with the suggested values.
private struct SetEntryRow: View {
  let exercise: Exercise
  let day: LocalDay
  @Environment(AppModel.self) private var model
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var weightText: String
  @State private var repsText: String
  @State private var problem: String?

  init(exercise: Exercise, day: LocalDay, suggestion: SetEntry?) {
    self.exercise = exercise
    self.day = day
    _weightText = State(initialValue: suggestion.map { copy.weightField($0.weight) } ?? "")
    _repsText = State(initialValue: suggestion.map { "\($0.reps.count)" } ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      let layout =
        typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
      let fields = SetFields(weightText: $weightText, repsText: $repsText, prefix: "")
      layout {
        fields.weight
        fields.reps
      }
      if let problem { InlineProblem(text: problem) }
      Button(action: record) {
        Label(copy[.logSet], systemImage: "plus")
      }
      .buttonStyle(MonoButtonStyle(prominent: true))
      .accessibilityIdentifier("log-set")
    }
  }

  private func record() {
    switch SetEntry.parse(weight: weightText, reps: repsText) {
    case .failure(let refusal):
      problem = copy.problem(entry: refusal)
    case .success(let entry):
      let command = Command.logSet(
        id: model.newSetID(), exerciseID: exercise.id, day: day, weight: entry.weight,
        reps: entry.reps)
      if model.perform(command) == .done { problem = nil }
    }
  }
}

/// The two inputs of a set, which the entry row and the set editor share.
struct SetFields {
  @Binding var weightText: String
  @Binding var repsText: String
  let prefix: String

  var weight: some View {
    LabeledField(
      label: copy[.weight], icon: "scalemass", unit: copy[.kilogramUnit],
      spokenLabel: copy[.weightSpoken], clearLabel: copy[.clearWeight],
      identifier: "\(prefix)weight", text: $weightText, keyboard: .decimalPad)
  }

  var reps: some View {
    LabeledField(
      label: copy[.reps], icon: "repeat", unit: copy[.repsUnit], spokenLabel: copy[.reps],
      clearLabel: copy[.clearReps], identifier: "\(prefix)reps", text: $repsText,
      keyboard: .numberPad)
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

  init(set: LoggedSet) {
    self.set = set
    _weightText = State(initialValue: copy.weightField(set.weight))
    _repsText = State(initialValue: "\(set.reps.count)")
  }

  var body: some View {
    SheetFrame(
      title: copy[.editSet], confirmTitle: copy[.save], confirmIcon: "checkmark", confirm: save
    ) {
      if let exercise = model.log.exercise(set.exerciseID) {
        GroupHeading(text: exercise.name.text, icon: "dumbbell")
      }
      let fields = SetFields(weightText: $weightText, repsText: $repsText, prefix: "edit-")
      fields.weight
      fields.reps
      if let problem { InlineProblem(text: problem) }
      Rule()
      Button {
        if model.perform(.deleteSet(id: set.id)) != .notStored { dismiss() }
      } label: {
        Label(copy[.deleteSet], systemImage: "trash")
      }
      .buttonStyle(MonoButtonStyle())
      .accessibilityIdentifier("delete-set")
    }
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

  init(day: LocalDay, text: String) {
    self.day = day
    _text = State(initialValue: text)
  }

  var body: some View {
    SheetFrame(
      title: copy[.note], confirmTitle: copy[.save], confirmIcon: "checkmark", confirm: save
    ) {
      Label(copy.noteCaption(day), systemImage: "note.text")
        .font(.subheadline.weight(.semibold))
      TextEditor(text: $text)
        .scrollContentBackground(.hidden)
        .background(.surface)
        .frame(minHeight: 180)
        .padding(8)
        .overlay { Rectangle().stroke(.ink, lineWidth: 1) }
        .accessibilityLabel(copy[.note])
        .accessibilityIdentifier("note-editor")
      Text(copy[.noteHint]).font(.subheadline)
      if let problem { InlineProblem(text: problem) }
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
