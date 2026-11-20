import GymemoCopy
import GymemoCore
import SwiftUI

private enum PreferenceKey {
  static let weightUnit = "gymemo-weight-unit"
  static let distanceUnit = "gymemo-distance-unit"
}

extension EnvironmentValues {
  @Entry var gymemoWeightUnit = WeightUnit.kilograms
  @Entry var gymemoDistanceUnit = DistanceUnit.kilometers
}

struct MeasurementPreferences: ViewModifier {
  @AppStorage(PreferenceKey.weightUnit) private var weightUnit = WeightUnit.kilograms
  #if !os(watchOS)
    @AppStorage(PreferenceKey.distanceUnit) private var distanceUnit = DistanceUnit.kilometers
  #endif

  func body(content: Content) -> some View {
    content.environment(\.gymemoWeightUnit, weightUnit)
      #if !os(watchOS)
        .environment(\.gymemoDistanceUnit, distanceUnit)
      #endif
  }
}

struct WeightUnitPicker: View {
  @AppStorage(PreferenceKey.weightUnit) private var unit = WeightUnit.kilograms

  var body: some View {
    #if os(iOS)
      UnitChoices(
        title: copy[.weightUnit], options: WeightUnit.allCases, selection: $unit,
        name: copy.weightUnitName, identifier: "weight-unit"
      )
    #else
      Picker(copy[.weightUnit], selection: $unit) {
        ForEach(WeightUnit.allCases, id: \.self) { unit in
          Text(copy.weightUnitName(unit)).tag(unit)
        }
      }
      .accessibilityIdentifier("weight-unit")
    #endif
  }
}

#if !os(watchOS)
  struct DistanceUnitPicker: View {
    @AppStorage(PreferenceKey.distanceUnit) private var unit = DistanceUnit.kilometers

    var body: some View {
      #if os(iOS)
        UnitChoices(
          title: copy[.distanceUnit], options: DistanceUnit.allCases, selection: $unit,
          name: copy.distanceUnitName, identifier: "distance-unit"
        )
      #else
        Picker(copy[.distanceUnit], selection: $unit) {
          ForEach(DistanceUnit.allCases, id: \.self) { unit in
            Text(copy.distanceUnitName(unit)).tag(unit)
          }
        }
        .accessibilityIdentifier("distance-unit")
      #endif
    }
  }
#endif

#if os(iOS)
  private struct UnitChoices<Unit: Hashable & RawRepresentable>: View
  where Unit.RawValue == String {
    let title: String
    let options: [Unit]
    @Binding var selection: Unit
    let name: (Unit) -> String
    let identifier: String

    var body: some View {
      Section(title) {
        ForEach(options, id: \.self) { unit in
          let isSelected = unit == selection
          Button {
            selection = unit
          } label: {
            HStack(alignment: .firstTextBaseline) {
              Text(name(unit)).font(.body).fixedSize(horizontal: false, vertical: true)
              Spacer()
              if isSelected {
                Image(systemName: "checkmark")
                  .foregroundStyle(Color.accentColor)
                  .accessibilityHidden(true)
              }
            }
          }
          .tint(Color.primary)
          .accessibilityAddTraits(isSelected ? .isSelected : [])
          .accessibilityIdentifier("\(identifier)-\(unit.rawValue)")
        }
      }
    }
  }
#endif
