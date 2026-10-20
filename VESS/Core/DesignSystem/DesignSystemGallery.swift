#if DEBUG
import SwiftUI

/// Every design system token and component on one screen, for checking
/// light mode, dark mode and Dynamic Type in Xcode Previews. Not shipped.
private struct DesignSystemGallery: View {
    @State private var weight = "68"
    @State private var allergies: Set<Allergen> = [.lactose]
    @State private var goal: WellnessGoal? = .buildMuscle

    var body: some View {
        NavigationStack {
            VESSScreen(title: "Design System") {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSWordmark()
                    Text("Temporary text wordmark")
                        .vessTextStyle(.label)
                }

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text("Good evening, Alex").vessTextStyle(.secondary)
                    Text("On track").vessTextStyle(.heroTitle)
                    Text("1,312 of 2,550 kcal. Protein is behind.")
                        .font(.body)
                        .foregroundStyle(VESSColor.secondaryText)
                }

                VESSSection(header: VESSSectionHeader(title: "Vessel Line")) {
                    VESSCard {
                        VStack(alignment: .leading, spacing: VESSSpacing.md) {
                            VESSMetric(value: Text(verbatim: "1,312"), context: Text("kcal"))
                            VESSMetric(value: Text(verbatim: "1,312"), context: Text("kcal"), style: .metricLarge)
                            VESSVesselLine(value: 0.51, tint: VESSColor.calories)
                            VESSVesselLine(value: 1.04, tint: VESSColor.calories)
                            VESSVesselLine(value: 0.72, tint: VESSColor.water, segments: 9)
                        }
                    }
                }

                VESSSection(header: VESSSectionHeader(title: "Rows", actionTitle: "Day diary", action: {})) {
                    VESSRowGroup(dividerInset: VESSSpacing.lg + 48 + VESSSpacing.sm) {
                        VESSRow(
                            title: Text(verbatim: "Breakfast"),
                            subtitle: Text(verbatim: "Rolled oats, Greek yogurt, strawberries"),
                            titleStyle: .rowTitle,
                            leading: { VESSThumbnail(systemImage: "sunrise") },
                            trailing: { Text(verbatim: "456").font(.body.monospacedDigit()) }
                        )
                        VESSRow(
                            title: Text("Add dinner").foregroundStyle(VESSColor.accent),
                            subtitle: Text("Usually around 19:30"),
                            leading: { VESSThumbnail(systemImage: "plus", isAction: true) },
                            trailing: { EmptyView() }
                        )
                    }
                    VESSRowGroup {
                        VESSRow(title: Text(verbatim: "Strawberries"), subtitle: Text(verbatim: "Fridge · 250 g")) {
                            VESSStatusBadge(text: Text("Tomorrow"), tone: .warning)
                        }
                        VESSRow(title: Text(verbatim: "Chicken breast"), subtitle: Text(verbatim: "Fridge · 500 g")) {
                            VESSStatusBadge(text: Text("In 2 days"))
                        }
                        VESSRow(title: Text(verbatim: "Spinach"), subtitle: Text(verbatim: "Fridge · 150 g")) {
                            VESSStatusBadge(text: Text("Today"), tone: .critical)
                        }
                    }
                }

                VESSMarginNote(
                    text: Text(verbatim: "Protein runs higher on days you have breakfast before 9:00."),
                    detail: Text(verbatim: "That happened 5 of the last 7 days.")
                )

                VESSSection(header: VESSSectionHeader(title: "Inputs")) {
                    VESSTextField("Weight", text: $weight, unit: "kg")
                        .keyboardType(.decimalPad)
                    VESSChipFlow {
                        ForEach(Allergen.allCases, id: \.self) { allergen in
                            VESSChip(title: allergen.title, isSelected: allergies.contains(allergen)) {
                                allergies.formSymmetricDifference([allergen])
                            }
                        }
                    }
                    VESSOptionRow(title: "Build muscle", isSelected: goal == .buildMuscle) { goal = .buildMuscle }
                    VESSOptionRow(title: "Eat healthier", detail: "More whole foods", isSelected: goal == .eatHealthier) { goal = .eatHealthier }
                }

                VStack(spacing: VESSSpacing.sm) {
                    Button("Continue") {}
                        .buttonStyle(.vessPrimary)
                    Button("Not now") {}
                        .buttonStyle(.vessSecondary)
                    Button("+250 ml") {}
                        .buttonStyle(.vessQuick)
                    Button {} label: { Label("Add to lunch", systemImage: "plus") }
                        .buttonStyle(.vessTertiary)
                    Button("Disabled") {}
                        .buttonStyle(.vessPrimary)
                        .disabled(true)
                }
            }
        }
    }
}

#Preview("Light") {
    DesignSystemGallery()
}

#Preview("Dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}

#Preview("Accessibility XL") {
    DesignSystemGallery()
        .dynamicTypeSize(.accessibility2)
}
#endif
