import Accessibility
import GymemoCopy
import GymemoCore
import GymemoKit
import SwiftUI

@main
struct GymemoWatchApp: App {
  @State private var model = try? WatchModel.open()

  var body: some Scene {
    WindowGroup {
      if let model {
        WatchHome().environment(model)
      } else {
        ContentUnavailableView {
          Label(copy[.launchFailed], systemImage: "exclamationmark.triangle")
        } description: {
          Text(copy[.launchStore])
        }
      }
    }
    .backgroundTask(.watchConnectivity) { await model?.finishBackgroundDelivery() }
  }
}

private struct WatchHome: View {
  @Environment(WatchModel.self) private var model
  @Environment(\.scenePhase) private var phase

  var body: some View {
    NavigationStack {
      List {
        if model.catalog.exercises.isEmpty {
          Section {
            Text(copy[.watchNeedsPhone]).accessibilityIdentifier("watch-needs-phone")
          } footer: {
            Text(copy[.watchHelp])
          }
        } else {
          Section(copy[.recentExercises]) {
            ForEach(model.catalog.exercises) { item in
              NavigationLink {
                WatchEntryScreen(item: item)
              } label: {
                Text(item.exercise.name.text)
              }
              .accessibilityIdentifier("watch-exercise-\(item.id.uuid.uuidString.lowercased())")
            }
          }
        }
        Section {
          NavigationLink(copy[.watchDelivery]) { WatchDeliveryScreen() }
            .accessibilityIdentifier("watch-delivery")
          NavigationLink(copy[.privacyPolicy]) { PrivacyScreen() }
            .accessibilityIdentifier("watch-privacy")
        }
      }
      .navigationTitle("gymemo")
      .onChange(of: phase) { _, phase in
        if phase == .active { model.resumeTransfers() }
      }
    }
  }
}

private struct WatchEntryScreen: View {
  let item: CompanionExercise
  @Environment(WatchModel.self) private var model
  @State private var weight: Weight
  @State private var reps: Reps
  @State private var lastLogged: SetID?
  @State private var logged = 0

  init(item: CompanionExercise) {
    self.item = item
    _weight = State(initialValue: item.suggestion?.weight ?? .bodyweight)
    _reps = State(initialValue: item.suggestion?.reps ?? .one)
  }

  var body: some View {
    ScrollViewReader { proxy in
      List {
        Section(copy[.weight]) {
          Stepper(onIncrement: { stepWeight(1) }, onDecrement: { stepWeight(-1) }) {
            Text(copy.load(weight)).font(.body).monospacedDigit()
          }
          .accessibilityLabel(copy[.weight])
          .accessibilityValue(copy.load(weight))
          .accessibilityIdentifier("watch-weight")
        }
        Section(copy[.reps]) {
          Stepper(onIncrement: { stepReps(1) }, onDecrement: { stepReps(-1) }) {
            Text(copy.repCount(reps.count)).font(.body).monospacedDigit()
          }
          .accessibilityLabel(copy[.reps])
          .accessibilityValue(copy.repCount(reps.count))
          .accessibilityIdentifier("watch-reps")
        }
        Section {
          Button(copy[.logSet], systemImage: "plus") {
            if let id = model.log(exercise: item.id, weight: weight, reps: reps) {
              lastLogged = id
              logged += 1
              AccessibilityNotification.Announcement(copy[.watchPending]).post()
            }
          }
          .handGestureShortcut(.primaryAction)
          .accessibilityIdentifier("watch-log-set")
        }
        if let lastLogged, let entry = model.entries.first(where: { $0.id == lastLogged }) {
          Section {
            WatchDeliveryRow(entry: entry)
              .id("watch-last-logged")
          } footer: {
            Text(copy[.watchWaitingHint])
          }
        }
        if let failure = model.failure { Text(failure) }
      }
      .onChange(of: lastLogged) { _, _ in
        proxy.scrollTo("watch-last-logged", anchor: .center)
      }
    }
    .navigationTitle(item.exercise.name.text)
    .sensoryFeedback(.success, trigger: logged)
  }

  private func stepWeight(_ steps: Int) {
    if let next = Weight.stepped(from: weight.text, by: steps) { weight = next }
  }

  private func stepReps(_ steps: Int) {
    if let next = Reps.stepped(from: "\(reps.count)", by: steps) { reps = next }
  }
}

private struct WatchDeliveryScreen: View {
  @Environment(WatchModel.self) private var model

  var body: some View {
    List {
      Section {
        ForEach(model.entries.reversed()) { entry in
          VStack(alignment: .leading) {
            if let name = entry.exerciseName {
              Text(name.text).font(.headline)
            }
            Text(copy.day(entry.set.day, .short)).foregroundStyle(Color.secondary)
            Text(copy.set(entry.set)).monospacedDigit()
            WatchDeliveryRow(entry: entry)
            if entry.outcome == nil || entry.outcome == .full {
              Button(copy[.retry]) { model.retry(entry.id) }
            }
          }
        }
      } footer: {
        Text(copy[.watchWaitingHint])
      }
      Section { Text(copy[.watchHelp]) }
      if let failure = model.failure { Text(failure) }
    }
    .navigationTitle(copy[.watchDelivery])
  }
}

private struct WatchDeliveryRow: View {
  let entry: CompanionQueuedSet

  var body: some View {
    switch entry.outcome {
    case .saved:
      Label(copy[.watchSaved], systemImage: "checkmark.circle")
        .accessibilityIdentifier("watch-saved")
    case nil:
      Label(copy[.watchPending], systemImage: "clock")
        .accessibilityIdentifier("watch-pending")
    case .unknownExercise: refusal(.watchExerciseMissing)
    case .identifierConflict: refusal(.watchIdentifierConflict)
    case .full: refusal(.watchPhoneFull)
    }
  }

  private func refusal(_ explanation: CopyKey) -> some View {
    VStack(alignment: .leading) {
      Label(copy[.watchRefused], systemImage: "exclamationmark.circle")
        .accessibilityIdentifier("watch-refused")
      Text(copy[explanation])
    }
  }
}
