import GymemoCore
import SwiftUI

/// Picks the exercise of the next set from recent ones and from each body part.
struct ExercisePicker: View {
  let pick: (Exercise) -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var isCreating = false

  var body: some View {
    let recent = model.log.recentExercises(limit: 5)
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          Button {
            isCreating = true
          } label: {
            Label("新しい種目を作る", systemImage: "plus")
          }
          .buttonStyle(MonoButtonStyle())
          .padding(.bottom, 20)
          if !recent.isEmpty {
            GroupHeading(text: "最近の種目", icon: "clock").padding(.bottom, 4)
            // A recent exercise also appears under its body part, so the two rows need different identities.
            ForEach(recent, id: \.name) { exercise in
              row(exercise).accessibilityIdentifier("recent-\(exercise.name.text)")
            }
          }
          ForEach(model.log.selectableExercises) { group in
            GroupHeading(
              text: Format.bodyPart(group.bodyPart), icon: "figure.strengthtraining.traditional"
            )
            .padding(.top, 24)
            .padding(.bottom, 4)
            ForEach(group.exercises) { exercise in
              row(exercise).accessibilityIdentifier("pick-\(exercise.name.text)")
            }
          }
        }
        .padding(16)
      }
      .background(.surface)
      .navigationTitle("種目を選ぶ")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Label("キャンセル", systemImage: "xmark").labelStyle(.titleAndIcon)
          }
        }
      }
      .sheet(isPresented: $isCreating) {
        ExerciseEditor(exercise: nil) { created in
          pick(created)
          dismiss()
        }
      }
    }
    .presentationBackground(.surface)
    .tint(.ink)
    .foregroundStyle(.ink)
  }

  private func row(_ exercise: Exercise) -> some View {
    RowButton {
      pick(exercise)
      dismiss()
    } label: {
      Label(exercise.name.text, systemImage: "dumbbell")
    }
  }
}

/// Creates an exercise, or changes the name, body part, and visibility of an existing one.
struct ExerciseEditor: View {
  let exercise: Exercise?
  var created: (Exercise) -> Void = { _ in }
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var bodyPart: BodyPart
  @State private var isSelectable: Bool
  @State private var problem: String?
  @State private var isConfirmingDelete = false

  init(exercise: Exercise?, created: @escaping (Exercise) -> Void = { _ in }) {
    self.exercise = exercise
    self.created = created
    _name = State(initialValue: exercise?.name.text ?? "")
    _bodyPart = State(initialValue: exercise?.bodyPart ?? .chest)
    _isSelectable = State(initialValue: !(exercise?.isArchived ?? false))
  }

  var body: some View {
    SheetFrame(
      title: exercise == nil ? "新しい種目" : "種目を直す", confirmTitle: "保存", confirmIcon: "checkmark",
      confirm: save
    ) {
      VStack(alignment: .leading, spacing: 4) {
        Label("名前", systemImage: "dumbbell").font(.subheadline.weight(.semibold))
        TextField("", text: $name)
          .font(.title3)
          .padding(.horizontal, 12)
          .frame(minHeight: 48)
          .overlay { Rectangle().stroke(.ink, lineWidth: 1) }
          .accessibilityLabel("名前")
          .accessibilityIdentifier("exercise-name")
        if let problem { InlineProblem(text: problem) }
      }
      VStack(alignment: .leading, spacing: 0) {
        GroupHeading(text: "部位", icon: "figure.strengthtraining.traditional").padding(.bottom, 4)
        ForEach(BodyPart.allCases, id: \.self) { part in
          ChoiceRow(text: Format.bodyPart(part), isSelected: part == bodyPart) { bodyPart = part }
        }
      }
      if let exercise {
        CheckRow(text: "種目を選ぶ一覧に出す", isOn: $isSelectable)
        deletion(of: exercise)
      }
    }
  }

  @ViewBuilder
  private func deletion(of exercise: Exercise) -> some View {
    if model.log.sets(of: exercise.id).isEmpty {
      Button {
        isConfirmingDelete = true
      } label: {
        Label("種目を削除", systemImage: "trash")
      }
      .buttonStyle(MonoButtonStyle())
      .confirmationDialog(
        "「\(exercise.name.text)」を削除しますか", isPresented: $isConfirmingDelete,
        titleVisibility: .visible
      ) {
        Button("削除", role: .destructive) {
          if model.perform(.deleteExercise(id: exercise.id)) != .notStored { dismiss() }
        }
        Button("キャンセル", role: .cancel) {}
      }
    } else {
      Label(Messages.exercise(.exerciseHasSets), systemImage: "info.circle")
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
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
      dismiss()
    }
  }

  /// Whether the command went through, after showing the reason when the log refused it.
  private func finish(_ outcome: PerformOutcome) -> Bool {
    switch outcome {
    case .done:
      return true
    case .refused(let refusal):
      problem = Messages.exercise(refusal)
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
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        Button {
          isCreating = true
        } label: {
          Label("新しい種目を作る", systemImage: "plus")
        }
        .buttonStyle(MonoButtonStyle())
        ForEach(model.log.exercisesByBodyPart) { group in
          GroupHeading(
            text: Format.bodyPart(group.bodyPart), icon: "figure.strengthtraining.traditional"
          )
          .padding(.top, 24)
          .padding(.bottom, 4)
          ForEach(group.exercises) { exercise in
            RowButton {
              edited = exercise
            } label: {
              HStack(spacing: 12) {
                Label(exercise.name.text, systemImage: "dumbbell")
                if exercise.isArchived { Badge(text: "一覧に出さない", icon: "eye.slash") }
                Spacer(minLength: 8)
                Image(systemName: "pencil")
              }
            }
            .accessibilityIdentifier("manage-\(exercise.name.text)")
          }
        }
      }
      .padding(16)
    }
    .background(.surface)
    .navigationTitle("種目の管理")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $edited) { exercise in
      ExerciseEditor(exercise: exercise)
    }
    .sheet(isPresented: $isCreating) {
      ExerciseEditor(exercise: nil)
    }
  }
}
