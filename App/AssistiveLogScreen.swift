#if os(iOS)
  import Accessibility
  import Combine
  import GymemoCopy
  import GymemoCore
  import SwiftUI

  private enum AssistiveRoute: Hashable {
    case exercises
    case weight(Exercise)
    case reps(Exercise, Weight)
    case review(Exercise, Weight, Reps)
    case saved(Exercise, LoggedSet)
  }

  struct AssistiveLogScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @State private var path: [AssistiveRoute] = []

    var body: some View {
      NavigationStack(path: $path) {
        List {
          Section {
            Text(copy.day(model.today, .long))
            Text(copy.setCount(model.log.sets(on: model.today).count))
            Button(copy[.logSet], systemImage: "plus") { path.append(.exercises) }
              .buttonStyle(.borderedProminent)
              .accessibilityIdentifier("assistive-start")
          }
        }
        .navigationTitle(copy[.tabLog])
        .navigationDestination(for: AssistiveRoute.self) { route in
          switch route {
          case .exercises:
            AssistiveExerciseChoice { path.append(.weight($0)) }
          case .weight(let exercise):
            AssistiveWeightStep(
              exercise: exercise,
              suggestion: model.log.suggestedEntry(for: exercise.id, on: model.today)
            ) { path.append(.reps(exercise, $0)) }
          case .reps(let exercise, let weight):
            AssistiveRepsStep(
              exercise: exercise,
              suggestion: model.log.suggestedEntry(for: exercise.id, on: model.today)
            ) { path.append(.review(exercise, weight, $0)) }
          case .review(let exercise, let weight, let reps):
            AssistiveSetReview(exercise: exercise, weight: weight, reps: reps) {
              path.append(.saved(exercise, $0))
            }
          case .saved(let exercise, let set):
            AssistiveSavedSet(exercise: exercise, set: set) {
              path = [.weight(exercise)]
            } done: {
              path.removeAll()
            }
          }
        }
      }
      .storageFailureAlert()
      .onOpenURL { _ in }
      .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
      .onChange(of: phase) { _, phase in
        if phase == .active { model.refreshToday() }
      }
      .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
        model.refreshToday()
      }
    }
  }

  private struct AssistiveExerciseChoice: View {
    let choose: (Exercise) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
      List {
        ForEach(model.log.selectableExercises) { group in
          Section(copy.bodyPart(group.bodyPart)) {
            ForEach(group.exercises) { exercise in
              Button(exercise.name.text) { choose(exercise) }
                .accessibilityIdentifier("assistive-exercise-\(exercise.name.text)")
            }
          }
        }
      }
      .navigationTitle(copy[.chooseExercise])
    }
  }

  private struct AssistiveWeightStep: View {
    let exercise: Exercise
    let next: (Weight) -> Void
    @State private var text: String
    @State private var problem: String?

    init(exercise: Exercise, suggestion: SetEntry?, next: @escaping (Weight) -> Void) {
      self.exercise = exercise
      self.next = next
      _text = State(initialValue: suggestion.map { copy.weightField($0.weight) } ?? "")
    }

    var body: some View {
      Form {
        Section {
          Text(exercise.name.text).font(.headline).accessibilityAddTraits(.isHeader)
          NumberFieldRow(
            kind: .weight, text: $text, identifier: "assistive-weight", exerciseName: exercise.name)
          if let problem { InlineProblem(text: problem, identifier: "assistive-problem") }
          Button(copy[.next], action: advance)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("assistive-next")
        }
      }
      .navigationTitle(copy[.weight])
      .keyboardDismissal()
    }

    private func advance() {
      switch SetEntry.parse(weight: text, reps: "1") {
      case .success(let entry):
        problem = nil
        next(entry.weight)
      case .failure(let refusal):
        problem = copy.problem(entry: refusal)
        AccessibilityNotification.Announcement(copy.problem(entry: refusal)).post()
      }
    }
  }

  private struct AssistiveRepsStep: View {
    let exercise: Exercise
    let next: (Reps) -> Void
    @State private var text: String
    @State private var problem: String?

    init(exercise: Exercise, suggestion: SetEntry?, next: @escaping (Reps) -> Void) {
      self.exercise = exercise
      self.next = next
      _text = State(initialValue: suggestion.map { "\($0.reps.count)" } ?? "1")
    }

    var body: some View {
      Form {
        Section {
          Text(exercise.name.text).font(.headline).accessibilityAddTraits(.isHeader)
          NumberFieldRow(
            kind: .reps, text: $text, identifier: "assistive-reps", exerciseName: exercise.name)
          if let problem { InlineProblem(text: problem, identifier: "assistive-problem") }
          Button(copy[.next], action: advance)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("assistive-next")
        }
      }
      .navigationTitle(copy[.reps])
      .keyboardDismissal()
    }

    private func advance() {
      switch Reps.parse(text) {
      case .success(let reps):
        problem = nil
        next(reps)
      case .failure(let refusal):
        problem = copy.problem(entry: .reps(refusal))
        AccessibilityNotification.Announcement(copy.problem(entry: .reps(refusal))).post()
      }
    }
  }

  private struct AssistiveSetReview: View {
    let exercise: Exercise
    let weight: Weight
    let reps: Reps
    let saved: (LoggedSet) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var problem: String?

    var body: some View {
      List {
        Section {
          Text(exercise.name.text).font(.headline).accessibilityAddTraits(.isHeader)
          Text(copy.set(weight: weight, reps: reps)).accessibilityIdentifier("assistive-summary")
          Button(copy[.logSet], systemImage: "plus", action: record)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("assistive-confirm")
          if let problem { InlineProblem(text: problem, identifier: "assistive-problem") }
        }
      }
      .navigationTitle(copy[.reviewSet])
    }

    private func record() {
      model.refreshToday()
      let set = LoggedSet(
        id: model.newSetID(), exerciseID: exercise.id, day: model.today, weight: weight, reps: reps)
      switch model.perform(
        .logSet(id: set.id, exerciseID: set.exerciseID, day: set.day, weight: weight, reps: reps),
        undoManager: undoManager)
      {
      case .done: saved(set)
      case .refused:
        problem = copy[.exerciseNotSaved]
        AccessibilityNotification.Announcement(copy[.exerciseNotSaved]).post()
      case .notStored: break
      }
    }
  }

  private struct AssistiveSavedSet: View {
    let exercise: Exercise
    let set: LoggedSet
    let again: () -> Void
    let done: () -> Void

    var body: some View {
      List {
        Section {
          Label(copy[.setSaved], systemImage: "checkmark.circle")
            .accessibilityIdentifier("assistive-saved")
          Text(exercise.name.text).font(.headline)
          Text(copy.set(set))
          Text(copy.day(set.day, .long))
          Button(copy[.logAnotherSet], action: again)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("assistive-again")
          Button(copy[.done], action: done).accessibilityIdentifier("assistive-done")
        }
      }
      .navigationTitle(copy[.setSaved])
    }
  }
#endif
