import GymemoCopy
import GymemoCore
import SwiftUI

/// Picks the exercise of the next set from recent ones and from each body part.
struct ExercisePicker: View {
  let pick: (Exercise) -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var isCreating = false

  private func matches(_ exercise: Exercise) -> Bool {
    query.isEmpty || exercise.name.text.localizedStandardContains(query)
  }

  var body: some View {
    let recent = query.isEmpty ? model.log.recentExercises(limit: 5) : []
    let groups = model.log.selectableExercises
    let hasMatch = groups.contains { $0.exercises.contains(where: matches) }
    NavigationStack {
      List {
        if !recent.isEmpty {
          Section(copy[.recentExercises]) {
            // A recent exercise also appears under its body part, so the two rows need different identities.
            ForEach(recent, id: \.name) { exercise in
              row(exercise).accessibilityIdentifier("recent-\(exercise.name.text)")
            }
          }
        }
        ForEach(groups) { group in
          let found = group.exercises.filter(matches)
          if !found.isEmpty {
            Section(copy.bodyPart(group.bodyPart)) {
              ForEach(found) { exercise in
                row(exercise).accessibilityIdentifier("pick-\(exercise.name.text)")
              }
            }
          }
        }
      }
      .overlay {
        if !hasMatch { ContentUnavailableView.search(text: query) }
      }
      .searchable(text: $query)
      .navigationTitle(copy[.chooseExercise])
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(copy[.cancel], systemImage: "xmark", role: .cancel) { dismiss() }
            .accessibilityIdentifier("sheet-cancel")
        }
        ToolbarItem(placement: .primaryAction) {
          Button(copy[.newExercise], systemImage: "plus") { isCreating = true }
            .accessibilityIdentifier("create-exercise")
        }
        // The search guidance places search at the bottom of the screen on an iPhone when there is room.
        // See https://developer.apple.com/design/human-interface-guidelines/search-fields.
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
      }
      .navigationDestination(isPresented: $isCreating) {
        ExerciseForm(exercise: nil, isPushed: true) { created in
          pick(created)
          dismiss()
        }
      }
    }
  }

  private func row(_ exercise: Exercise) -> some View {
    Button(exercise.name.text) {
      pick(exercise)
      dismiss()
    }
    .tint(.primary)
  }
}

/// A sheet that creates an exercise, or changes the name, body part, and visibility of an existing one.
struct ExerciseEditor: View {
  let exercise: Exercise?

  var body: some View {
    NavigationStack {
      ExerciseForm(exercise: exercise, isPushed: false)
    }
  }
}

/// The fields of an exercise, inside a sheet of its own or pushed inside the exercise picker.
struct ExerciseForm: View {
  let exercise: Exercise?
  let isPushed: Bool
  var created: (Exercise) -> Void = { _ in }
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var bodyPart: BodyPart
  @State private var isSelectable: Bool
  @State private var problem: String?
  @State private var isConfirmingDelete = false

  init(exercise: Exercise?, isPushed: Bool, created: @escaping (Exercise) -> Void = { _ in }) {
    self.exercise = exercise
    self.isPushed = isPushed
    self.created = created
    _name = State(initialValue: exercise?.name.text ?? "")
    _bodyPart = State(initialValue: exercise?.bodyPart ?? .chest)
    _isSelectable = State(initialValue: !(exercise?.isArchived ?? false))
  }

  private var title: String { exercise == nil ? copy[.newExercise] : copy[.editExercise] }

  private var isDirty: Bool {
    name != (exercise?.name.text ?? "") || bodyPart != (exercise?.bodyPart ?? .chest)
      || isSelectable == (exercise?.isArchived ?? false)
  }

  var body: some View {
    let form = Form {
      Section {
        TextField(copy[.name], text: $name)
          .accessibilityIdentifier("exercise-name")
        if let problem { InlineProblem(text: problem) }
        Picker(copy[.bodyPart], selection: $bodyPart) {
          ForEach(BodyPart.allCases, id: \.self) { part in
            Text(copy.bodyPart(part)).tag(part)
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("body-part")
      }
      if let exercise {
        Section {
          Toggle(copy[.showWhenChoosing], isOn: $isSelectable)
            .accessibilityIdentifier("selectable")
        }
        deletion(of: exercise)
      }
    }
    if isPushed {
      form
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(copy[.save], systemImage: "checkmark", role: .confirm, action: save)
              .accessibilityIdentifier("sheet-confirm")
          }
        }
    } else {
      form.sheetToolbar(title: title, confirmTitle: copy[.save], isDirty: isDirty, confirm: save)
    }
  }

  @ViewBuilder
  private func deletion(of exercise: Exercise) -> some View {
    if model.log.sets(of: exercise.id).isEmpty {
      Section {
        Button(copy[.deleteExercise], role: .destructive) { isConfirmingDelete = true }
          .accessibilityIdentifier("delete-exercise")
          // The confirmation opens from the button behind it, as the adoption guide asks.
          // See https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass.
          .confirmationDialog(
            copy.deleteQuestion(exercise.name), isPresented: $isConfirmingDelete,
            titleVisibility: .visible
          ) {
            Button(copy[.delete], role: .destructive) {
              if model.perform(.deleteExercise(id: exercise.id)) != .notStored { dismiss() }
            }
            Button(copy[.cancel], role: .cancel) {}
          }
      }
    } else {
      Section {
      } footer: {
        Text(copy.problem(exercise: .exerciseHasSets))
      }
    }
  }

  private func save() {
    if let exercise {
      let edit = Command.editExercise(id: exercise.id, name: name, bodyPart: bodyPart)
      guard finish(model.perform(edit)) else { return }
      let archive = Command.setExerciseArchived(id: exercise.id, isArchived: !isSelectable)
      if finish(model.perform(archive)) { dismiss() }
    } else {
      let id = model.newExerciseID()
      guard finish(model.perform(.addExercise(id: id, name: name, bodyPart: bodyPart))) else {
        return
      }
      if let added = model.log.exercise(id) { created(added) }
      if !isPushed { dismiss() }
    }
  }

  /// Whether the command went through, after showing the reason when the log refused it.
  private func finish(_ outcome: PerformOutcome) -> Bool {
    switch outcome {
    case .done:
      return true
    case .refused(let refusal):
      problem = copy.problem(exercise: refusal)
      return false
    case .notStored:
      return false
    }
  }
}

/// Every exercise by body part, for renaming, hiding, and deleting.
struct ExerciseListScreen: View {
  @Environment(AppModel.self) private var model
  @State private var edited: Exercise?
  @State private var isCreating = false

  var body: some View {
    List {
      ForEach(model.log.exercisesByBodyPart) { group in
        Section(copy.bodyPart(group.bodyPart)) {
          ForEach(group.exercises) { exercise in
            let toggleTitle = exercise.isArchived ? copy[.show] : copy[.hide]
            let toggleSymbol = exercise.isArchived ? "eye" : "eye.slash"
            Button {
              edited = exercise
            } label: {
              LabeledContent(exercise.name.text) {
                if exercise.isArchived { Text(copy[.hidden]) }
              }
            }
            .tint(.primary)
            .accessibilityIdentifier("manage-\(exercise.name.text)")
            .swipeActions(edge: .trailing) {
              Button(toggleTitle, systemImage: toggleSymbol) { toggle(exercise) }
            }
            .contextMenu {
              Button(toggleTitle, systemImage: toggleSymbol) { toggle(exercise) }
              Button(copy[.editExercise], systemImage: "pencil") { edited = exercise }
            }
          }
        }
      }
    }
    .navigationTitle(copy[.exercises])
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(copy[.newExercise], systemImage: "plus") { isCreating = true }
          .accessibilityIdentifier("create-exercise")
      }
    }
    .sheet(item: $edited) { exercise in
      ExerciseEditor(exercise: exercise)
    }
    .sheet(isPresented: $isCreating) {
      ExerciseEditor(exercise: nil)
    }
  }

  private func toggle(_ exercise: Exercise) {
    model.perform(.setExerciseArchived(id: exercise.id, isArchived: !exercise.isArchived))
  }
}
