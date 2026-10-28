import SwiftUI

// MARK: - Shared header

/// A diary section header: TRACKED CAPS title with a quiet detail at the
/// trailing edge, such as "540 kcal · 07:45", or "—" when empty.
private struct DiaryHeader: View {
    let title: LocalizedStringResource
    var detail: Text?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                titleText
                Spacer(minLength: VESSSpacing.md)
                detailText
            }
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                titleText
                detailText
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var titleText: some View {
        Text(title)
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.secondaryText)
    }

    private var detailText: some View {
        (detail ?? Text(verbatim: "—"))
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
    }
}

// MARK: - Day totals

/// The day's total, what's left, and the three macro bars.
struct DiaryTotals: View {
    let summary: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xl) {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text(VESSFormat.calories(summary.consumed.calories))
                        .vessTextStyle(.displayL)
                        .foregroundStyle(VESSColor.text)
                    Text("kcal")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                Text(balanceText)
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calories")
            .accessibilityValue(Text(accessibilityValue))

            VStack(spacing: VESSSpacing.lg) {
                macro("Protein", consumed: summary.consumed.proteinGrams, target: summary.targets.proteinGrams, metric: .protein)
                macro("Carbs", consumed: summary.consumed.carbohydrateGrams, target: summary.targets.carbohydrateGrams, metric: .carbs)
                macro("Fat", consumed: summary.consumed.fatGrams, target: summary.targets.fatGrams, metric: .fat)
            }

            if let note = unreportedNote {
                Text(note)
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func macro(_ name: LocalizedStringResource, consumed: Double, target: Double, metric: VESSMetricKind) -> some View {
        VESSMacroBar(
            name: name,
            value: VESSFormat.grams(consumed),
            target: target > 0 ? "/ \(VESSFormat.grams(target))\u{00A0}g" : "g",
            adding: target > 0 ? consumed / target : 0,
            metric: metric
        )
    }

    /// "of 2,400 kcal · 560 left", or "· 25 above" past the target. Never red.
    private var balanceText: String {
        let target = summary.targets.calories
        guard target > 0 else { return String(localized: "No daily target set.") }
        let remaining = summary.caloriesRemaining
        let balance = remaining >= 0
            ? String(localized: "\(VESSFormat.calories(remaining)) left")
            : String(localized: "\(VESSFormat.calories(-remaining)) above")
        return String(localized: "of \(VESSFormat.calories(target))\u{00A0}kcal · \(balance)")
    }

    private var accessibilityValue: String {
        let consumed = VESSFormat.calories(summary.consumed.calories)
        guard summary.targets.calories > 0 else {
            return String(localized: "\(consumed)\u{00A0}kcal. No daily target set.")
        }
        let remaining = summary.caloriesRemaining
        let balance = remaining >= 0
            ? String(localized: "\(VESSFormat.calories(remaining))\u{00A0}kcal left")
            : String(localized: "\(VESSFormat.calories(-remaining))\u{00A0}kcal above your target")
        return String(localized: "\(consumed) of \(VESSFormat.calories(summary.targets.calories))\u{00A0}kcal. \(balance)")
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

// MARK: - Meal

/// One meal: header, its items as a hairline list, then "Add to …". An
/// empty meal shows its usual time and what's left instead of items.
struct MealDiarySection: View {
    let meal: MealType
    let entries: [FoodLogEntry]
    /// "Usually around 19:30 · 560 kcal left", for an empty meal.
    var emptyNote: Text?
    let onAdd: () -> Void
    let onEdit: (FoodLogEntry) -> Void
    let onDelete: (FoodLogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            DiaryHeader(title: meal.title, detail: detail)

            if entries.isEmpty {
                if let emptyNote {
                    emptyNote
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VESSRowGroup {
                    ForEach(entries) { entry in
                        row(for: entry)
                    }
                }
                .vessListChanges(entries.map(\.id))
                .vessHairlineBottom()
            }

            Button(action: onAdd) {
                Text(entries.isEmpty ? meal.addTitle : meal.addToTitle)
            }
            .buttonStyle(.vessSecondary)
            .padding(.top, VESSSpacing.xs)
            .accessibilityIdentifier("nutrition.add.\(meal.rawValue)")
        }
    }

    private func row(for entry: FoodLogEntry) -> some View {
        Button {
            onEdit(entry)
        } label: {
            VESSRow(title: Text(entry.foodName), subtitle: subtitle(for: entry)) {
                Text("\(VESSFormat.calories(entry.nutrition.calories))\u{00A0}kcal")
                    .vessTextStyle(.bodyM)
                    .monospacedDigit()
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Edit or delete"))
        .accessibilityIdentifier("entry.\(entry.foodName)")
        .contextMenu {
            Button("Edit", systemImage: "pencil") { onEdit(entry) }
            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(entry) }
        }
        .accessibilityAction(named: "Delete") { onDelete(entry) }
    }

    private var detail: Text? {
        guard let first = entries.first else { return nil }
        return Text("\(VESSFormat.calories(entries.totalNutrition.calories))\u{00A0}kcal · \(first.loggedAt, format: .dateTime.hour().minute())")
    }

    /// "1 tbsp · 21 g", "200 g", "150 g · Estimated" or "Quick add".
    private func subtitle(for entry: FoodLogEntry) -> Text {
        if entry.source == .photoEstimate {
            if let menu = entry.menuName {
                return Text("\(Text(verbatim: entry.servingUnit.amountText(entry.quantity))) · \(menu) · Estimated")
            }
            return Text("\(Text(verbatim: entry.servingUnit.amountText(entry.quantity))) · Estimated")
        }
        if entry.foodID == nil {
            guard entry.nutrition.isReported(.protein) else { return Text("Quick add") }
            return Text("Quick add · \(VESSFormat.grams(entry.nutrition.proteinGrams))\u{00A0}g protein")
        }
        if let label = entry.portionLabel, entry.portionAmount != nil {
            let count = entry.portionCount
            let total = Text(verbatim: entry.servingUnit.amountText(entry.quantity))
            return count == 1
                ? Text("\(label) · \(total)")
                : Text("\(VESSFormat.quantity(count)) × \(label) · \(total)")
        }
        return Text(verbatim: entry.servingUnit.amountText(entry.quantity))
    }
}

// MARK: - Drinks

/// Drinks for the day. Repeated water is one row ("3 glasses · last at
/// 17:05"); other drinks show volume, time and how much counts toward
/// hydration, with caffeine as the value when they have any.
struct DrinksDiarySection: View {
    let day: Date
    let logs: [HydrationLog]
    let onAdd: () -> Void
    let onDelete: (HydrationLog) -> Void

    var body: some View {
        let caffeine = logs.reduce(0) { $0 + $1.caffeineMilligrams }

        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            DiaryHeader(title: "Drinks")

            if !logs.isEmpty {
                VESSRowGroup {
                    ForEach(groups) { group in
                        row(for: group)
                    }
                }
                .vessListChanges(groups.map(\.id))
                .vessHairlineBottom()
            }

            // To the caffeine screen: the day's total against the limit.
            NavigationLink {
                CaffeineView(day: day)
            } label: {
                VESSListRow(
                    systemImage: "cup.and.saucer",
                    title: Text("Caffeine"),
                    subtitle: logs.last(where: { $0.caffeineMilligrams > 0 }).map { Text("Last at \($0.loggedAt, format: .dateTime.hour().minute())") },
                    value: Text("\(VESSFormat.grams(caffeine)) of \(VESSFormat.grams(CaffeineModel.dailyLimitMilligrams))\u{00A0}mg")
                )
            }
            .buttonStyle(.plain)
            .vessHairlineBottom()
            .accessibilityIdentifier("nutrition.caffeine")

            Button("Add a drink", action: onAdd)
                .buttonStyle(.vessSecondary)
                .padding(.top, VESSSpacing.xs)
                .accessibilityIdentifier("nutrition.addDrink")
        }
    }

    /// Water logs with the same name form one group; every other drink is its own.
    private var groups: [DrinkGroup] {
        var result: [DrinkGroup] = []
        for log in logs {
            if log.drinkType == .water, let index = result.firstIndex(where: { $0.isWater && $0.name == log.drinkName }) {
                result[index].logs.append(log)
            } else {
                result.append(DrinkGroup(logs: [log]))
            }
        }
        return result
    }

    private func row(for group: DrinkGroup) -> some View {
        let deleteTitle: LocalizedStringResource = group.logs.count > 1 ? "Delete last glass" : "Delete"
        return VESSRow(title: Text(group.name), subtitle: subtitle(for: group)) {
            Text(value(for: group))
                .vessTextStyle(.bodyM)
                .monospacedDigit()
                .foregroundStyle(VESSColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button(role: .destructive) {
                onDelete(group.latest)
            } label: {
                Label { Text(deleteTitle) } icon: { Image(systemName: "trash") }
            }
        }
        .accessibilityAction(named: Text(deleteTitle)) { onDelete(group.latest) }
    }

    private func subtitle(for group: DrinkGroup) -> Text {
        let latest = group.latest
        let time = Text(latest.loggedAt, format: .dateTime.hour().minute())
        if group.logs.count > 1 {
            return Text("^[\(group.logs.count) glass](inflect: true) · last at \(time)")
        }
        let volume = Text("\(VESSFormat.milliliters(latest.volumeMilliliters))\u{00A0}ml")
        // "330 ml · 18:40 · 13 g alcohol · 1.3 drinks"
        if latest.isAlcoholic, let grams = latest.alcoholGrams {
            return Text("\(volume) · \(time) · \(VESSFormat.grams(grams))\u{00A0}g alcohol · \(DrinkFacts.drinksText(StandardDrink.count(alcoholGrams: grams)))")
        }
        if latest.hydrationContributionPercent < 100 {
            return Text("\(volume) · \(time) · counts as \(VESSFormat.milliliters(latest.hydrationMilliliters))\u{00A0}ml")
        }
        return Text("\(volume) · \(time)")
    }

    /// kcal for alcohol (they count in the day's energy); caffeine when the
    /// drink has any; otherwise the volume (litres for a group).
    private func value(for group: DrinkGroup) -> String {
        let alcoholCalories = group.logs.reduce(0) { $0 + $1.alcoholCalories }
        if group.logs.contains(where: \.isAlcoholic) { return "\(VESSFormat.calories(alcoholCalories))\u{00A0}kcal" }
        let caffeine = group.logs.reduce(0) { $0 + $1.caffeineMilligrams }
        if caffeine > 0 { return "\(VESSFormat.grams(caffeine))\u{00A0}mg" }
        let volume = group.logs.reduce(0) { $0 + $1.volumeMilliliters }
        return group.logs.count > 1
            ? "\(VESSFormat.liters(fromMilliliters: volume))\u{00A0}L"
            : "\(VESSFormat.milliliters(volume))\u{00A0}ml"
    }
}

private struct DrinkGroup: Identifiable {
    var logs: [HydrationLog]

    var id: UUID { logs[0].id }
    var name: String { logs[0].drinkName }
    var isWater: Bool { logs[0].drinkType == .water }
    var latest: HydrationLog { logs.max { $0.loggedAt < $1.loggedAt } ?? logs[0] }
}
