import SwiftUI

// MARK: - Shared header

/// A diary section header: title, quiet detail beside it, and the section's
/// own add action at the trailing edge. Keeps every meal to one header line
/// plus its entries, with no separate "Add" link below.
private struct DiaryHeader: View {
    let title: LocalizedStringResource
    var detail: Text?
    let addLabel: LocalizedStringResource
    var addIdentifier: String?
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: VESSSpacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    titleText
                    detail?.vessTextStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: VESSSpacing.xxs / 2) {
                    titleText
                    detail?.vessTextStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            VESSHeaderAddButton(label: addLabel, action: onAdd)
                .accessibilityIdentifier(addIdentifier ?? "")
        }
    }

    private var titleText: some View {
        Text(title)
            .vessTextStyle(.sectionTitle)
    }
}

// MARK: - Empty day

/// An empty day as one short list: every meal and drinks, each a single tap
/// from logging. Replaces five bare section headers.
struct EmptyDiaryList: View {
    let onAddFood: (MealType) -> Void
    let onAddDrink: () -> Void

    var body: some View {
        VESSRowGroup {
            ForEach(MealType.dayOrder) { meal in
                row(title: meal.title, label: meal.addToTitle) { onAddFood(meal) }
            }
            row(title: "Drinks", label: "Add a drink", identifier: "nutrition.addDrink", action: onAddDrink)
        }
    }

    private func row(
        title: LocalizedStringResource,
        label: LocalizedStringResource,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VESSRow(title: Text(title), titleStyle: .rowTitle) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VESSColor.accent)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier ?? "")
    }
}

// MARK: - Meal

struct MealDiarySection: View {
    let meal: MealType
    let entries: [FoodLogEntry]
    let onAdd: () -> Void
    let onDelete: (FoodLogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            DiaryHeader(title: meal.title, detail: detail, addLabel: meal.addToTitle, onAdd: onAdd)

            if !entries.isEmpty {
                VESSRowGroup {
                    ForEach(entries) { entry in
                        VESSRow(
                            title: Text(entry.foodName),
                            subtitle: subtitle(for: entry),
                            trailing: {
                                Text(VESSFormat.calories(entry.nutrition.calories))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(VESSColor.text)
                            }
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(Text("\(VESSFormat.calories(entry.nutrition.calories)) kcal"))
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(entry) }
                        }
                        .accessibilityAction(named: "Delete") { onDelete(entry) }
                    }
                }
            }
        }
    }

    private var detail: Text? {
        guard let first = entries.first else { return nil }
        return Text("\(VESSFormat.calories(entries.totalNutrition.calories)) kcal · \(first.loggedAt, format: .dateTime.hour().minute())")
    }

    private func subtitle(for entry: FoodLogEntry) -> Text {
        if entry.foodID == nil {
            return Text("Quick add · \(VESSFormat.grams(entry.nutrition.proteinGrams)) g protein")
        }
        if entry.servingUnit == .piece {
            return Text("^[\(VESSFormat.quantity(entry.quantity)) piece](inflect: true)")
        }
        return Text("\(VESSFormat.quantity(entry.quantity)) \(Text(entry.servingUnit.abbreviation))")
    }
}

// MARK: - Drinks

/// Drinks for the day. Each row shows the volume drunk and, separately, how
/// much of it counts toward hydration.
struct DrinksDiarySection: View {
    let logs: [HydrationLog]
    let onAdd: () -> Void
    let onDelete: (HydrationLog) -> Void

    var body: some View {
        let caffeine = logs.reduce(0) { $0 + $1.caffeineMilligrams }

        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            DiaryHeader(
                title: "Drinks",
                detail: caffeine > 0 ? Text("Caffeine \(VESSFormat.grams(caffeine)) mg") : nil,
                addLabel: "Add a drink",
                addIdentifier: "nutrition.addDrink",
                onAdd: onAdd
            )

            if !logs.isEmpty {
                VESSRowGroup {
                    ForEach(logs) { log in
                        VESSRow(
                            title: Text(log.drinkName),
                            subtitle: subtitle(for: log),
                            trailing: {
                                Text("\(VESSFormat.milliliters(log.volumeMilliliters)) ml")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(VESSColor.text)
                            }
                        )
                        .accessibilityElement(children: .combine)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(log) }
                        }
                        .accessibilityAction(named: "Delete") { onDelete(log) }
                    }
                }
            }

            if let lastCaffeine = logs.last(where: { $0.caffeineMilligrams > 0 }) {
                Text("Your last caffeine was at \(lastCaffeine.loggedAt, format: .dateTime.hour().minute()).")
                    .vessTextStyle(.label)
                    .padding(.top, VESSSpacing.xs)
            }
        }
    }

    private func subtitle(for log: HydrationLog) -> Text {
        let time = Text(log.loggedAt, format: .dateTime.hour().minute())
        if log.hydrationContributionPercent < 100 {
            return Text("\(time) · counts as \(VESSFormat.milliliters(log.hydrationMilliliters)) ml")
        }
        return time
    }
}
