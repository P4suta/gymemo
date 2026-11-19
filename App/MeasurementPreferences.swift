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
    Picker(copy[.weightUnit], selection: $unit) {
      ForEach(WeightUnit.allCases, id: \.self) { unit in
        Text(copy.weightUnitName(unit)).tag(unit)
      }
    }
    .accessibilityIdentifier("weight-unit")
  }
}

#if !os(watchOS)
  struct DistanceUnitPicker: View {
    @AppStorage(PreferenceKey.distanceUnit) private var unit = DistanceUnit.kilometers

    var body: some View {
      Picker(copy[.distanceUnit], selection: $unit) {
        ForEach(DistanceUnit.allCases, id: \.self) { unit in
          Text(copy.distanceUnitName(unit)).tag(unit)
        }
      }
      .accessibilityIdentifier("distance-unit")
    }
  }
#endif
