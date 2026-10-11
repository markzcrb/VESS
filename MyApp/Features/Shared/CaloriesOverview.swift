import SwiftUI

/// Calories and macros for a day, set directly on the page (no card):
/// the number, its Vessel Line, what's left, then the three macros.
/// Shared by Today (hero size) and Nutrition (compact) so a day always reads the same.
struct CaloriesOverview: View {
    enum Prominence {
        case hero
        case compact
    }

    let summary: DaySummary
    var prominence: Prominence = .hero

    var body: some View {
        let consumed = summary.consumed.calories
        let target = summary.targets.calories

        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                VESSMetric(
                    value: Text(VESSFormat.calories(consumed)),
                    context: Text("of \(VESSFormat.calories(target)) kcal"),
                    style: prominence == .hero ? .metricHero : .metric
                )

                VESSVesselLine(value: target > 0 ? consumed / target : 0, tint: VESSColor.calories)

                Text(remainingText)
                    .vessTextStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calories")
            .accessibilityValue(Text("\(VESSFormat.calories(consumed)) of \(VESSFormat.calories(target)) kcal. \(remainingText)"))

            MacroSummaryView(consumed: summary.consumed, targets: summary.targets)
                .padding(.top, VESSSpacing.xs)

            if let note = unreportedNote {
                Text(note)
                    .vessTextStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Macro totals only count what was reported; say so rather than imply zero.
    private var unreportedNote: String? {
        guard let unreported = summary.consumed.unreportedCoreNutrients?.subtracting([.calories]),
              !unreported.isEmpty else { return nil }
        let names = CoreNutrient.allCases
            .filter(unreported.contains)
            .map { String(localized: $0.inlineName) }
            .formatted(.list(type: .and))
        return String(localized: "Some foods don't report \(names), so those totals may be low.")
    }

    private var remainingText: String {
        let remaining = summary.caloriesRemaining
        return remaining >= 0
            ? String(localized: "\(VESSFormat.calories(remaining)) kcal left")
            : String(localized: "\(VESSFormat.calories(-remaining)) kcal above your target")
    }
}
