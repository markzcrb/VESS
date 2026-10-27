import SwiftUI

/// Protein, carbs and fat side by side, each with a Vessel Line.
/// Stacks vertically at accessibility text sizes.
struct MacroSummaryView: View {
    let consumed: NutritionFacts
    let targets: NutritionTargets

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: VESSSpacing.lg))

        layout {
            MacroColumn(title: "Protein", tint: VESSColor.protein, value: consumed.proteinGrams, target: targets.proteinGrams)
            MacroColumn(title: "Carbs", tint: VESSColor.carbs, value: consumed.carbohydrateGrams, target: targets.carbohydrateGrams)
            MacroColumn(title: "Fat", tint: VESSColor.fat, value: consumed.fatGrams, target: targets.fatGrams)
        }
    }
}

private struct MacroColumn: View {
    let title: LocalizedStringKey
    let tint: Color
    let value: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            VESSDotLabel(title: title, tint: tint)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(VESSFormat.grams(value))
                    .foregroundStyle(VESSColor.text)
                Text(verbatim: " / \(VESSFormat.grams(target))\u{00A0}g")
                    .foregroundStyle(VESSColor.secondaryText)
            }
            .font(.callout.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            VESSVesselLine(value: target > 0 ? value / target : 0, tint: tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text("\(VESSFormat.grams(value)) of \(VESSFormat.grams(target)) grams"))
    }
}
