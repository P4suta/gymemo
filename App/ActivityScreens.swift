import Accessibility
import GymemoCopy
import GymemoCore
import SwiftUI

struct ActivitySection: View {
  let records: [LoggedActivity]
  let edit: (LoggedActivity) -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.undoManager) private var undoManager
  @Environment(\.gymemoDistanceUnit) private var unit

  var body: some View {
    Section(copy[.activities]) {
      ForEach(records) { record in
        if let activity = model.log.activities.activity(record.activityID) {
          let name = copy.timedActivityName(activity)
          Button {
            edit(record)
          } label: {
            StackedRow(title: name, subtitle: copy.activityRecord(record, unit: unit))
          }
          .accessibilityIdentifier("activity-\(record.id.uuid.uuidString)")
          .accessibilityElement(children: .combine)
          .tint(Color.primary)
          .swipeActions(edge: .trailing) {
            Button(copy[.delete], systemImage: "trash", role: .destructive) { delete(record) }
            Button(copy[.edit], systemImage: "pencil") { edit(record) }
          }
          .contextMenu {
            Button(copy[.edit], systemImage: "pencil") { edit(record) }
            Button(copy[.delete], systemImage: "trash", role: .destructive) { delete(record) }
          }
        }
      }
    }
  }

  private func delete(_ record: LoggedActivity) {
    model.perform(.delete(record.id), undoManager: undoManager)
  }
}

struct ActivityDefinitionForm: View {
  let created: (TimedActivity) -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.undoManager) private var undoManager
  @State private var name = ""
  @State private var tracksDistance = false
  @State private var problem: String?

  var body: some View {
    Form {
      Section {
        TextField(copy[.name], text: $name)
          .accessibilityIdentifier("timed-activity-name")
        if let problem { InlineProblem(text: problem) }
        Picker(copy[.recordMeasure], selection: $tracksDistance) {
          Text(copy[.timeOnly]).tag(false)
          Text(copy[.timeAndDistance]).tag(true)
        }
        .pickerStyle(.menu)
      }
    }
    .navigationTitle(copy[.newActivity])
    .toolbarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(copy[.save], systemImage: "checkmark", role: .confirm, action: save)
          .accessibilityIdentifier("sheet-confirm")
      }
    }
  }

  private func save() {
    let id = TimedActivityID(UUID())
    switch model.perform(
      .add(id: id, name: name, tracksDistance: tracksDistance), undoManager: undoManager)
    {
    case .done:
      if let activity = model.log.activities.activity(id) { created(activity) }
    case .refused(let refusal):
      problem = copy.problem(activity: refusal)
    case .notStored:
      break
    }
  }
}

struct ActivityRecordForm: View {
  enum Presentation {
    case sheet, assistive
  }

  let activity: TimedActivity
  let day: LocalDay
  let record: LoggedActivity?
  let presentation: Presentation
  let saved: () -> Void
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.undoManager) private var undoManager
  @State private var unit: DistanceUnit
  @State private var originalDistance: String
  @State private var minutes: String
  @State private var distance: String
  @State private var invalidDuration = false
  @State private var invalidDistance = false
  @State private var problem: String?

  init(
    activity: TimedActivity, day: LocalDay, unit: DistanceUnit, record: LoggedActivity? = nil,
    presentation: Presentation, saved: @escaping () -> Void = {}
  ) {
    self.activity = activity
    self.day = day
    self.record = record
    self.presentation = presentation
    self.saved = saved
    let original = record?.distance.map { copy.distanceField($0, unit: unit) } ?? ""
    _unit = State(initialValue: unit)
    _originalDistance = State(initialValue: original)
    _minutes = State(initialValue: record.map { String($0.duration.minutes) } ?? "")
    _distance = State(initialValue: original)
  }

  private var title: String { copy.timedActivityName(activity) }

  private var isDirty: Bool {
    minutes != (record.map { String($0.duration.minutes) } ?? "") || distance != originalDistance
  }

  var body: some View {
    switch presentation {
    case .sheet:
      NavigationStack {
        form.sheetToolbar(
          title: copy[record == nil ? .logActivity : .editActivity], confirmTitle: copy[.save],
          isDirty: isDirty, confirm: save)
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    case .assistive:
      form.navigationTitle(title)
    }
  }

  private var form: some View {
    Form {
      Section {
        ActivityInputRow(
          title: copy[.duration], text: $minutes, identifier: "activity-duration")
        if invalidDuration {
          InlineProblem(text: copy[.durationProblem], identifier: "activity-duration-problem")
        }
        if activity.tracksDistance {
          ActivityInputRow(
            title: copy[.optionalDistance], text: $distance, identifier: "activity-distance",
            unit: unit)
          if invalidDistance {
            InlineProblem(text: copy[.distanceProblem], identifier: "activity-distance-problem")
          }
        }
        if let problem { InlineProblem(text: problem) }
      } header: {
        Text(title)
      }
      if let record {
        Section {
          Button(role: .destructive) {
            if model.perform(.delete(record.id), undoManager: undoManager) == .done {
              dismiss()
            }
          } label: {
            Label {
              Text(copy[.deleteActivity]).foregroundStyle(Color.primary)
            } icon: {
              Image(systemName: "trash").foregroundStyle(.red)
            }
          }
          .accessibilityIdentifier("delete-activity")
        }
      }
      if presentation == .assistive {
        Button(copy[.save], action: save)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("sheet-confirm")
      }
    }
    .dismissKeyboardWhenScrolling()
    .keyboardDismissal()
  }

  private func save() {
    let duration = ActivityDuration.parse(minutes)
    let hasDistance =
      activity.tracksDistance
      && !distance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let length = hasDistance ? parsedDistance : nil
    invalidDuration = duration == nil
    invalidDistance = hasDistance && length == nil
    guard let duration, !invalidDistance else {
      AccessibilityNotification.Announcement(
        copy[invalidDuration ? .durationProblem : .distanceProblem]
      ).post()
      return
    }
    let command: ActivityCommand
    if let record {
      command = .edit(record.id, duration: duration, distance: length)
    } else {
      command = .record(
        LoggedActivity(
          id: LoggedActivityID(UUID()), activityID: activity.id, day: day, duration: duration,
          distance: length))
    }
    switch model.perform(command, undoManager: undoManager) {
    case .done:
      AccessibilityNotification.Announcement(copy[.activitySaved]).post()
      if presentation == .sheet { dismiss() } else { saved() }
    case .refused(let refusal):
      problem = copy.problem(activity: refusal)
    case .notStored:
      break
    }
  }

  private var parsedDistance: ActivityDistance? {
    if distance == originalDistance, let existing = record?.distance { return existing }
    return unit.parse(distance)
  }
}

private struct ActivityInputRow: View {
  let title: String
  @Binding var text: String
  let identifier: String
  var unit: DistanceUnit?
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(spacing: 12))
    layout {
      Text(title).accessibilityHidden(true)
      HStack(spacing: 8) {
        TextField("", text: $text)
          .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
          .numberKeyboard(unit == nil ? .reps : .weight)
          .numericInput(identifier: identifier)
          .accessibilityLabel(
            unit.map { [title, copy.distanceUnitName($0)].joined(separator: copy[.listSeparator]) }
              ?? title)
        if let unit {
          Text(unit.rawValue).accessibilityHidden(true)
        }
      }
    }
    .id(identifier)
  }
}
