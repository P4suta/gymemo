import SwiftUI

/// A full-width button drawn with the two palette colors, filled when prominent or pressed.
struct MonoButtonStyle: ButtonStyle {
  var prominent = false

  func makeBody(configuration: Configuration) -> some View {
    let filled = prominent != configuration.isPressed
    configuration.label
      .font(.body.weight(.semibold))
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.horizontal, 12)
      .foregroundStyle(filled ? .surface : .ink)
      .background(filled ? .ink : .surface)
      .overlay { Rectangle().stroke(.ink, lineWidth: 2) }
      .contentShape(Rectangle())
  }
}

/// A row that acts as one button across its whole width, with a solid rule below it.
struct RowButton<Label: View>: View {
  let action: () -> Void
  @ViewBuilder let label: () -> Label

  var body: some View {
    Button(action: action) {
      label()
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) { Rule() }
  }
}

/// A solid line that separates two groups.
struct Rule: View {
  var body: some View {
    Rectangle().fill(.ink).frame(height: 1).accessibilityHidden(true)
  }
}

/// The heading of a group of rows or values.
struct GroupHeading: View {
  let text: String
  let icon: String

  var body: some View {
    Label(text, systemImage: icon)
      .font(.headline)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A short state word in a solid frame, such as a personal best.
struct Badge: View {
  let text: String
  let icon: String

  var body: some View {
    Label(text, systemImage: icon)
      .font(.footnote.weight(.bold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .overlay { Rectangle().stroke(.ink, lineWidth: 1) }
  }
}

/// What is wrong with an input and how to fix it, shown next to the input.
struct InlineProblem: View {
  let text: String

  var body: some View {
    Label(text, systemImage: "exclamationmark.triangle")
      .font(.subheadline.weight(.semibold))
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("problem")
  }
}

/// One option of a single choice, marked by a filled circle when selected.
struct ChoiceRow: View {
  let text: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    RowButton(action: action) {
      Label(text, systemImage: isSelected ? "largecircle.fill.circle" : "circle")
        .fontWeight(isSelected ? .bold : .regular)
    }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// A setting that is on or off, marked by a checked square when on.
struct CheckRow: View {
  let text: String
  @Binding var isOn: Bool

  var body: some View {
    RowButton {
      isOn.toggle()
    } label: {
      Label(text, systemImage: isOn ? "checkmark.square" : "square")
    }
    .accessibilityValue(isOn ? "オン" : "オフ")
  }
}

/// A one-line input with its label above it and its unit after it, inside a solid frame.
struct LabeledField: View {
  let label: String
  let icon: String
  let unit: String
  let spokenLabel: String
  @Binding var text: String
  let keyboard: UIKeyboardType

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Label(label, systemImage: icon).font(.subheadline.weight(.semibold))
      HStack(spacing: 8) {
        TextField("", text: $text)
          .keyboardType(keyboard)
          .font(.title3.monospacedDigit())
          .multilineTextAlignment(.trailing)
          .accessibilityLabel(spokenLabel)
        Text(unit).accessibilityHidden(true)
      }
      .padding(.horizontal, 12)
      .frame(minHeight: 48)
      .overlay { Rectangle().stroke(.ink, lineWidth: 1) }
    }
  }
}

/// The frame of every sheet: a title, a cancel button, and one confirming action.
struct SheetFrame<Content: View>: View {
  let title: String
  let confirmTitle: String
  let confirmIcon: String
  let confirm: () -> Void
  @ViewBuilder let content: () -> Content
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          content()
        }
        .padding(16)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(.surface)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Label("キャンセル", systemImage: "xmark").labelStyle(.titleAndIcon)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(action: confirm) {
            Label(confirmTitle, systemImage: confirmIcon).labelStyle(.titleAndIcon)
          }
        }
      }
    }
    .presentationBackground(.surface)
    .tint(.ink)
    .foregroundStyle(.ink)
  }
}
