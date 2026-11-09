import GymemoCopy
import GymemoCore
import SwiftUI

/// The trophy and the words that mark a personal best.
/// The words carry the meaning, and the accent color only draws the eye.
struct PersonalBestMark: View {
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "trophy.fill").foregroundStyle(Color.accentColor)
      Text(copy[.personalBest]).foregroundStyle(Color.secondary)
    }
    .font(.footnote)
    .accessibilityElement(children: .combine)
  }
}

/// One logged set: its number, its load and repetitions, and the mark of a personal best.
/// At the accessibility text sizes the mark moves below the set, so the set wraps across the full width.
struct SetRow: View {
  let number: Int
  let set: LoggedSet
  let isBest: Bool
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    layout {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(number.formatted(.number.locale(copy.locale))).foregroundStyle(Color.secondary)
        Text(copy.set(set)).foregroundStyle(Color.primary)
      }
      .monospacedDigit()
      if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
      if isBest { PersonalBestMark() }
    }
  }
}

/// The value that a number row edits.
enum NumberKind {
  case weight, reps
}

/// A labeled number field with its unit and a stepper.
/// The stepper changes the value without the keyboard: 2.5 kg for a weight and one for repetitions.
/// At the accessibility text sizes the label, the field, and the stepper stack, so no number is clipped.
struct NumberFieldRow: View {
  let kind: NumberKind
  @Binding var text: String
  let identifier: String
  @FocusState private var isFocused: Bool
  @Environment(\.dynamicTypeSize) private var typeSize

  private var title: String { kind == .weight ? copy[.weight] : copy[.reps] }

  var body: some View {
    let isLarge = typeSize.isAccessibilitySize
    let layout =
      isLarge
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(spacing: 12))
    layout {
      Text(title)
      HStack(spacing: 4) {
        TextField(title, text: $text, prompt: Text(kind == .weight ? copy[.bodyweight] : ""))
          .keyboardType(kind == .weight ? .decimalPad : .numberPad)
          .multilineTextAlignment(isLarge ? .leading : .trailing)
          .monospacedDigit()
          .focused($isFocused)
          .accessibilityLabel(kind == .weight ? copy[.weightSpoken] : copy[.reps])
          .accessibilityIdentifier(identifier)
        if kind == .weight {
          Text(copy[.kilogramUnit]).foregroundStyle(Color.secondary).accessibilityHidden(true)
        }
        if isFocused && !text.isEmpty {
          Button {
            text = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .frame(minWidth: 32, minHeight: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.secondary)
          .accessibilityLabel(kind == .weight ? copy[.clearWeight] : copy[.clearReps])
          .accessibilityIdentifier("clear-\(identifier)")
        }
      }
      Stepper(title, onIncrement: { step(1) }, onDecrement: { step(-1) })
        .labelsHidden()
        .accessibilityIdentifier("step-\(identifier)")
    }
  }

  private func step(_ steps: Int) {
    switch kind {
    case .weight:
      guard let weight = Weight.stepped(from: text, by: steps) else { return }
      text = weight.isBodyweight ? "" : copy.weightField(weight)
    case .reps:
      guard let reps = Reps.stepped(from: text, by: steps) else { return }
      text = "\(reps.count)"
    }
  }
}

/// What is wrong with an input and how to fix it, in a row under the fields.
/// The symbol is red, and the message stays in the label color so that it reads at any contrast.
struct InlineProblem: View {
  let text: String
  var identifier = "problem"

  var body: some View {
    Label {
      Text(text).foregroundStyle(Color.primary)
    } icon: {
      Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
    }
    .font(.footnote)
    .accessibilityIdentifier(identifier)
  }
}

/// The result of an action, with a symbol that states success or failure.
struct NoticeRow: View {
  let text: String
  let isFailure: Bool

  var body: some View {
    Label {
      Text(text).foregroundStyle(Color.primary)
    } icon: {
      if isFailure {
        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
      } else {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
      }
    }
  }
}

/// Lines of text that wrap instead of truncating: an optional line above, a title, and up to two lines below.
struct StackedRow: View {
  var overline: String?
  let title: String
  var subtitle: String?
  var caption: String?
  var isEmphasized = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let overline { Text(overline).font(.subheadline).foregroundStyle(Color.secondary) }
      Text(title).font(isEmphasized ? .headline : .body).foregroundStyle(Color.primary)
      if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Color.secondary) }
      if let caption { Text(caption).font(.subheadline).foregroundStyle(Color.secondary) }
    }
  }
}

extension View {
  /// Adds a button over the keyboard that puts it away, because the number pads have no return key.
  /// A standard toolbar there takes the system material.
  func keyboardDismissal() -> some View {
    toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(copy[.hideKeyboard], systemImage: "keyboard.chevron.compact.down") {
          UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .accessibilityIdentifier("hide-keyboard")
      }
    }
  }

  /// The toolbar of a sheet: a cancel button, one confirming button, and a question before unsaved changes are discarded.
  /// The sheet guidance puts Cancel at the leading edge and the confirming action at the trailing edge.
  /// See https://developer.apple.com/design/human-interface-guidelines/sheets.
  func sheetToolbar(
    title: String, confirmTitle: String, isDirty: Bool, confirm: @escaping () -> Void
  ) -> some View {
    modifier(
      SheetToolbar(title: title, confirmTitle: confirmTitle, isDirty: isDirty, confirm: confirm))
  }
}

private struct SheetToolbar: ViewModifier {
  let title: String
  let confirmTitle: String
  let isDirty: Bool
  let confirm: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var isAskingToDiscard = false

  func body(content: Content) -> some View {
    content
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(isDirty)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(copy[.cancel], systemImage: "xmark", role: .cancel) {
            if isDirty { isAskingToDiscard = true } else { dismiss() }
          }
          .accessibilityIdentifier("sheet-cancel")
          .confirmationDialog(
            copy[.discardQuestion], isPresented: $isAskingToDiscard, titleVisibility: .visible
          ) {
            Button(copy[.discardChanges], role: .destructive) { dismiss() }
            // An anchored confirmation shows no button with the cancel role, so this choice takes no role.
            Button(copy[.keepEditing]) {}
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(confirmTitle, systemImage: "checkmark", role: .confirm, action: confirm)
            .accessibilityIdentifier("sheet-confirm")
        }
      }
  }
}
