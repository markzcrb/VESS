import SwiftUI

/// Calories, then macros, then any optional nutrients the source reported.
/// Unreported values read "Not reported", never "0".
struct NutrientList: View {
    let nutrition: NutritionFacts

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                Text("Calories")
                    .vessTextStyle(.label)
                if nutrition.isReported(.calories) {
                    VESSMetric(value: Text(VESSFormat.calories(nutrition.calories)), context: Text("kcal"))
                        .accessibilityElement(children: .combine)
                } else {
                    Text("Not reported")
                        .vessTextStyle(.metric)
                        .foregroundStyle(VESSColor.secondaryText)
                }
            }

            VESSRowGroup {
                row(.protein, nutrition.proteinGrams, tint: VESSColor.protein)
                row(.carbohydrates, nutrition.carbohydrateGrams, tint: VESSColor.carbs)
                row(.fat, nutrition.fatGrams, tint: VESSColor.fat)
                if let fiber = nutrition.fiberGrams {
                    optionalRow("Fibre", value: "\(VESSFormat.quantity(fiber))\u{00A0}g")
                }
                if let sugar = nutrition.sugarGrams {
                    optionalRow("Sugars", value: "\(VESSFormat.quantity(sugar))\u{00A0}g")
                }
                if let sodium = nutrition.sodiumMilligrams {
                    optionalRow("Sodium", value: "\(VESSFormat.milliliters(sodium))\u{00A0}mg")
                }
            }
        }
    }

    private func row(_ nutrient: CoreNutrient, _ grams: Double, tint: Color) -> some View {
        VESSRow(title: Text(nutrient.title)) {
            if nutrition.isReported(nutrient) {
                Text("\(VESSFormat.quantity(grams))\u{00A0}g")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(VESSColor.text)
            } else {
                Text("Not reported")
                    .vessTextStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func optionalRow(_ title: LocalizedStringKey, value: String) -> some View {
        VESSRow(title: Text(title)) {
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(VESSColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
