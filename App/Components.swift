import GymemoCopy
import GymemoCore
import SwiftUI

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
/// At accessibility text sizes, the vertical stack keeps the label, field, and stepper visible.
struct NumberFieldRow: View {
  let kind: NumberKind
  @Binding var text: String
  let identifier: String
  var exerciseName: ExerciseName?
  @FocusState private var isFocused: Bool
  @Environment(\.dynamicTypeSize) private var typeSize

  private var title: String { kind == .weight ? copy[.weight] : copy[.reps] }

  private var spokenTitle: String {
    let title = kind == .weight ? copy[.weightSpoken] : copy[.reps]
    return exerciseName.map { copy.exerciseControlTitle(title, $0) } ?? title
  }

  private var spokenValue: String {
    switch kind {
    case .weight:
      if case .success(let entry) = SetEntry.parse(weight: text, reps: "1") {
        return copy.load(entry.weight)
      }
    case .reps:
      if case .success(let reps) = Reps.parse(text) { return copy.repCount(reps.count) }
    }
    return text
  }

  var body: some View {
    let isLarge = typeSize.isAccessibilitySize
    let layout =
      isLarge
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(spacing: 12))
    layout {
      HStack {
        Text(title)
          .foregroundStyle(Color.primary)
          .accessibilityIdentifier("label-\(identifier)")
        if isLarge && kind == .weight {
          Spacer()
          unitLabel
        }
      }
      HStack(spacing: 4) {
        TextField(
          title, text: $text,
          prompt: kind == .weight && text.isEmpty ? Text(copy[.bodyweight]) : nil
        )
        .numberKeyboard(kind)
        .multilineTextAlignment(isLarge ? .leading : .trailing)
        .monospacedDigit()
        .focused($isFocused)
        #if os(iOS)
          .focusedValue(\.gymemoNumberInput, identifier)
        #endif
        .accessibilityLabel(spokenTitle)
        .accessibilityInputLabels([spokenTitle, title])
        .accessibilityIdentifier(identifier)
        if !isLarge && kind == .weight { unitLabel }
        if !isLarge { clearControl }
      }
      HStack {
        Stepper(spokenTitle, onIncrement: { step(1) }, onDecrement: { step(-1) })
          .labelsHidden()
          .accessibilityValue(spokenValue)
          .accessibilityInputLabels([spokenTitle, title])
          .accessibilityIdentifier("step-\(identifier)")
        if isLarge {
          Spacer()
          clearControl
        }
      }
    }
    .id(identifier)
  }

  private var unitLabel: some View {
    Text(copy[.kilogramUnit])
      .foregroundStyle(Color.primary)
      .accessibilityHidden(true)
      .accessibilityIdentifier("unit-\(identifier)")
  }

  @ViewBuilder
  private var clearControl: some View {
    if isFocused && !text.isEmpty {
      Button {
        text = ""
      } label: {
        clearSymbol
      }
      .buttonStyle(.plain)
      .foregroundStyle(Color.secondary)
      .accessibilityLabel(kind == .weight ? copy[.clearWeight] : copy[.clearReps])
      .accessibilityIdentifier("clear-\(identifier)")
    } else {
      clearSymbol.hidden()
    }
  }

  private var clearSymbol: some View {
    Image(systemName: "xmark.circle.fill")
      #if os(visionOS)
        .frame(minWidth: 60, minHeight: 60)
      #elseif os(macOS)
        .frame(minWidth: 28, minHeight: 28)
      #else
        .frame(minWidth: 44, minHeight: 44)
      #endif
      .contentShape(Rectangle())
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

/// Explains an invalid input and its correction under the fields.
/// The symbol uses red, and the message uses the label color.
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(text)
  }
}

/// A wrapping title with optional preceding and following text.
struct StackedRow: View {
  var overline: String?
  let title: String
  var subtitle: String?
  var caption: String?
  var isEmphasized = false
  var isSelected = false

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let overline { rowText(overline, secondary: true).font(.subheadline) }
      rowText(title, secondary: false).font(isEmphasized ? .headline : .body)
      if let subtitle { rowText(subtitle, secondary: true).font(.subheadline) }
      if let caption { rowText(caption, secondary: true).font(.subheadline) }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  @ViewBuilder
  private func rowText(_ value: String, secondary: Bool) -> some View {
    if isSelected {
      Text(value)
    } else {
      Text(value).foregroundStyle(secondary ? Color.secondary : Color.primary)
    }
  }
}

extension View {
  func storageFailureAlert() -> some View {
    modifier(StorageFailureAlert())
  }

  @ViewBuilder
  func dismissKeyboardWhenScrolling() -> some View {
    #if os(visionOS)
      self
    #else
      scrollDismissesKeyboard(.interactively)
    #endif
  }

  @ViewBuilder
  func numberKeyboard(_ kind: NumberKind) -> some View {
    #if os(iOS) || os(visionOS)
      keyboardType(kind == .weight ? .decimalPad : .numberPad)
    #else
      self
    #endif
  }

  /// Adds a button over the keyboard that puts it away, because the number pads have no return key.
  /// A standard toolbar there takes the system material.
  func keyboardDismissal() -> some View {
    #if os(iOS)
      modifier(KeyboardDismissal())
    #else
      self
    #endif
  }

  /// Provides the sheet actions and confirms discarding unsaved input.
  /// The sheet guidance puts Cancel at the leading edge and the confirming action at the trailing edge.
  /// See https://developer.apple.com/design/human-interface-guidelines/sheets.
  func sheetToolbar(
    title: String, confirmTitle: String, isDirty: Bool, confirm: @escaping () -> Void
  ) -> some View {
    modifier(
      SheetToolbar(title: title, confirmTitle: confirmTitle, isDirty: isDirty, confirm: confirm))
  }
}

#if os(iOS)
  extension FocusedValues {
    @Entry fileprivate var gymemoNumberInput: String?
  }

  private struct KeyboardDismissal: ViewModifier {
    @FocusedValue(\.gymemoNumberInput) private var focusedInput

    func body(content: Content) -> some View {
      ScrollViewReader { reader in
        content
          .onChange(of: focusedInput) { _, identifier in
            if let identifier { reader.scrollTo(identifier, anchor: .center) }
          }
          .onGeometryChange(for: CGSize.self) {
            CGSize(width: $0.size.width, height: $0.size.height - $0.safeAreaInsets.bottom)
          } action: { _ in
            if let focusedInput { reader.scrollTo(focusedInput, anchor: .center) }
          }
          .toolbar {
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
    }
  }
#endif

private struct StorageFailureAlert: ViewModifier {
  @Environment(AppModel.self) private var model

  func body(content: Content) -> some View {
    @Bindable var model = model
    content.alert(
      copy[.saveFailed], isPresented: Binding(isPresent: $model.storeFailure),
      presenting: model.storeFailure
    ) { _ in
    } message: { failure in
      Text(copy.saveFailedMessage(code: failure.code))
    }
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
      .toolbarTitleDisplayMode(.inline)
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
