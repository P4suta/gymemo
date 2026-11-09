import GymemoCore
import SwiftUI

/// The input that holds the keyboard on a day's screen.
enum DayField: Hashable {
  case weight(ExerciseID)
  case reps(ExerciseID)
}

/// One day's sets and memo, for today in the Log tab and for any other day from History.
struct DayScreen: View {
  let day: LocalDay
  @Environment(AppModel.self) private var model
  @State private var pending: [ExerciseID] = []
  @State private var isPickingExercise = false
  @State private var isEditingMemo = false
  @State private var editedSet: LoggedSet?
  @FocusState private var focus: DayField?

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
          Label("今日ではない日の記録です", systemImage: "calendar").font(.subheadline.weight(.semibold))
        }
        MemoBlock(memo: model.log.memo(on: day)) { isEditingMemo = true }
        if sections.isEmpty {
          Text("種目を追加して、最初のセットを記録します。")
            .accessibilityIdentifier("empty-day")
        }
        ForEach(sections) { section in
          Rule()
          ExerciseBlock(
            exercise: section.exercise, sets: section.sets, day: day, bests: bests,
            previous: model.log.previousSession(of: section.exercise.id, before: day),
            suggestion: model.log.suggestedEntry(for: section.exercise.id, on: day), focus: $focus
          ) { editedSet = $0 }
        }
        Rule()
        Button {
          isPickingExercise = true
        } label: {
          Label("種目を追加", systemImage: "plus")
        }
        .buttonStyle(MonoButtonStyle(prominent: sections.isEmpty))
      }
      .padding(16)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(.surface)
    .navigationTitle(Format.longDay(day))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button {
          focus = nil
        } label: {
          Label("キーボードを閉じる", systemImage: "keyboard.chevron.compact.down")
            .labelStyle(.titleAndIcon)
        }
      }
    }
    .sheet(isPresented: $isPickingExercise) {
      ExercisePicker { exercise in
        if !pending.contains(exercise.id) { pending.append(exercise.id) }
      }
    }
    .sheet(isPresented: $isEditingMemo) {
      MemoEditor(day: day, text: model.log.memo(on: day)?.text ?? "")
    }
    .sheet(item: $editedSet) { set in
      SetEditor(set: set)
    }
  }
}

private struct MemoBlock: View {
  let memo: Memo?
  let edit: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let memo {
        GroupHeading(text: "メモ", icon: "note.text")
        Text(memo.text).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("memo-text")
      }
      Button(action: edit) {
        Label(memo == nil ? "メモを書く" : "メモを直す", systemImage: "square.and.pencil")
      }
      .buttonStyle(MonoButtonStyle())
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
  let focus: FocusState<DayField?>.Binding
  let edit: (LoggedSet) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      GroupHeading(text: exercise.name.text, icon: "dumbbell").font(.title3.bold())
      if let previous {
        Text(
          "前回 \(Format.shortDay(previous.day))　\(previous.sets.map(Format.set).joined(separator: "、"))"
        )
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("previous-session")
      }
      VStack(spacing: 0) {
        ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
          SetRow(number: index + 1, set: set, isBest: bests.contains(set.id)) { edit(set) }
        }
      }
      SetEntryRow(exercise: exercise, day: day, suggestion: suggestion, focus: focus)
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
        Text("\(number)").font(.body.monospacedDigit()).frame(minWidth: 24, alignment: .leading)
        // At the accessibility sizes the badge moves below the set, so neither wraps inside a narrow column.
        let layout =
          typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
          : AnyLayout(HStackLayout(spacing: 12))
        layout {
          Text(Format.set(set)).font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
          if isBest { Badge(text: "自己ベスト", icon: "trophy") }
        }
        Spacer(minLength: 8)
        Image(systemName: "pencil")
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Format.spokenSet(set, number: number, isBest: isBest))
    .accessibilityHint("重量と回数を直すか、セットを削除します。")
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("set-\(number)")
  }
}

/// The weight and repetitions of the next set, already filled with the suggested values.
private struct SetEntryRow: View {
  let exercise: Exercise
  let day: LocalDay
  let focus: FocusState<DayField?>.Binding
  @Environment(AppModel.self) private var model
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var weightText: String
  @State private var repsText: String
  @State private var problem: String?

  init(
    exercise: Exercise, day: LocalDay, suggestion: SetEntry?, focus: FocusState<DayField?>.Binding
  ) {
    self.exercise = exercise
    self.day = day
    self.focus = focus
    let weight = suggestion.map(\.weight)
    _weightText = State(initialValue: weight.map { $0.isBodyweight ? "" : $0.text } ?? "")
    _repsText = State(initialValue: suggestion.map { "\($0.reps.count)" } ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      let layout =
        typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        : AnyLayout(HStackLayout(alignment: .bottom, spacing: 12))
      layout {
        LabeledField(
          label: "重量", icon: "scalemass", unit: "kg", spokenLabel: "重量、キログラム",
          text: $weightText, keyboard: .decimalPad
        )
        .focused(focus, equals: .weight(exercise.id))
        .accessibilityIdentifier("weight")
        LabeledField(
          label: "回数", icon: "repeat", unit: "回", spokenLabel: "回数", text: $repsText,
          keyboard: .numberPad
        )
        .focused(focus, equals: .reps(exercise.id))
        .accessibilityIdentifier("reps")
      }
      if let problem { InlineProblem(text: problem) }
      Button(action: record) {
        Label("セットを記録", systemImage: "plus")
      }
      .buttonStyle(MonoButtonStyle(prominent: true))
    }
  }

  private func record() {
    switch SetEntry.parse(weight: weightText, reps: repsText) {
    case .failure(let refusal):
      problem = Messages.entry(refusal)
    case .success(let entry):
      let command = Command.logSet(
        id: model.newSetID(), exerciseID: exercise.id, day: day, weight: entry.weight,
        reps: entry.reps)
      if model.perform(command) == .done { problem = nil }
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

  init(set: LoggedSet) {
    self.set = set
    _weightText = State(initialValue: set.weight.isBodyweight ? "" : set.weight.text)
    _repsText = State(initialValue: "\(set.reps.count)")
  }

  var body: some View {
    SheetFrame(title: "セットを直す", confirmTitle: "保存", confirmIcon: "checkmark", confirm: save) {
      if let exercise = model.log.exercise(set.exerciseID) {
        GroupHeading(text: exercise.name.text, icon: "dumbbell")
      }
      LabeledField(
        label: "重量", icon: "scalemass", unit: "kg", spokenLabel: "重量、キログラム", text: $weightText,
        keyboard: .decimalPad
      )
      .accessibilityIdentifier("edit-weight")
      LabeledField(
        label: "回数", icon: "repeat", unit: "回", spokenLabel: "回数", text: $repsText,
        keyboard: .numberPad
      )
      .accessibilityIdentifier("edit-reps")
      if let problem { InlineProblem(text: problem) }
      Rule()
      Button {
        if model.perform(.deleteSet(id: set.id)) != .notStored { dismiss() }
      } label: {
        Label("セットを削除", systemImage: "trash")
      }
      .buttonStyle(MonoButtonStyle())
    }
  }

  private func save() {
    switch SetEntry.parse(weight: weightText, reps: repsText) {
    case .failure(let refusal):
      problem = Messages.entry(refusal)
    case .success(let entry):
      let command = Command.editSet(id: set.id, weight: entry.weight, reps: entry.reps)
      if model.perform(command) != .notStored { dismiss() }
    }
  }
}

/// Writes, changes, or clears the memo of one day.
struct MemoEditor: View {
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
    SheetFrame(title: "メモ", confirmTitle: "保存", confirmIcon: "checkmark", confirm: save) {
      Label("\(Format.longDay(day))のメモ", systemImage: "note.text")
        .font(.subheadline.weight(.semibold))
      TextEditor(text: $text)
        .scrollContentBackground(.hidden)
        .background(.surface)
        .frame(minHeight: 180)
        .padding(8)
        .overlay { Rectangle().stroke(.ink, lineWidth: 1) }
        .accessibilityLabel("メモ")
        .accessibilityIdentifier("memo-editor")
      Text("空にして保存すると、メモを消します。").font(.subheadline)
      if let problem { InlineProblem(text: problem) }
    }
  }

  private func save() {
    switch model.perform(.writeMemo(day: day, text: text)) {
    case .done: dismiss()
    case .refused(let refusal): problem = Messages.memo(refusal)
    case .notStored: break
    }
  }
}
