import SwiftUI

/// Calories and macros for a day, set directly on the page (no card).
///
/// One composition: the eaten total leads, with what's left and the target
/// beside it on the same baseline, the Vessel Line beneath, then the macros.
/// Shared by Today (hero size) and Nutrition (large) so a day always reads
/// the same. Over target shows "above", never red; a missing target shows
/// the total alone.
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
                // Beside the number when it fits; below it at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.md) {
                        metric
                        Spacer(minLength: 0)
                        if target > 0 { balance(alignment: .trailing) }
                    }
                    VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                        metric
                        if target > 0 { balance(alignment: .leading) }
                    }
                }
                if target > 0 {
                    VESSVesselLine(value: consumed / target, tint: VESSColor.calories)
                } else {
                    Text("No daily target set.")
                        .vessTextStyle(.label)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calories")
            .accessibilityValue(Text(accessibilityValue))

            MacroSummaryView(consumed: summary.consumed, targets: summary.targets)
                .padding(.top, VESSSpacing.xs)

            if let note = unreportedNote {
                Text(note)
                    .vessTextStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metric: some View {
        VESSMetric(
            value: Text(VESSFormat.calories(summary.consumed.calories)),
            context: Text("kcal"),
            style: prominence == .hero ? .metricHero : .metricLarge
        )
    }

    /// "1,238 left" over "of 2,550", or "25 above" when past the target.
    private func balance(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: VESSSpacing.xxs / 2) {
            Text(balanceText)
                .font(.body.monospacedDigit())
                .foregroundStyle(VESSColor.text)
            Text("of \(VESSFormat.calories(summary.targets.calories))")
                .vessTextStyle(.label)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var balanceText: String {
        let remaining = summary.caloriesRemaining
        if summary.consumed.calories == 0 {
            return String(localized: "\(VESSFormat.calories(remaining)) to go")
        }
        return remaining >= 0
            ? String(localized: "\(VESSFormat.calories(remaining)) left")
            : String(localized: "\(VESSFormat.calories(-remaining)) above")
    }

    private var accessibilityValue: String {
        let consumed = VESSFormat.calories(summary.consumed.calories)
        guard summary.targets.calories > 0 else {
            return String(localized: "\(consumed) kcal. No daily target set.")
        }
        let remaining = summary.caloriesRemaining
        let balance = remaining >= 0
            ? String(localized: "\(VESSFormat.calories(remaining)) kcal left")
            : String(localized: "\(VESSFormat.calories(-remaining)) kcal above your target")
        return String(localized: "\(consumed) of \(VESSFormat.calories(summary.targets.calories)) kcal. \(balance)")
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
}
