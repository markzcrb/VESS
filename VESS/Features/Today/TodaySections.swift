import SwiftUI

// The sections of the Today screen. Each takes plain values and closures,
// so it can be previewed and reasoned about on its own.
//
// Composition rule: lists of items (meals, expiring food) sit in a card;
// single measures (calories, water, activity) sit open on the page.

// MARK: - Header and Day Word

struct TodayHeader: View {
    let date: Date
    let greeting: String
    let summary: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            // Greeting and date share one quiet line above the Day Word.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs - 2) {
                    greetingText
                    Text(verbatim: "·")
                        .vessTextStyle(.label)
                        .accessibilityHidden(true)
                    dateText
                }
                VStack(alignment: .leading, spacing: VESSSpacing.xxs / 2) {
                    greetingText
                    dateText
                }
            }

            Text(summary.dayWord.title)
                .vessTextStyle(.heroTitle)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today.dayWord")

            Text(summary.sentence)
                .font(.body)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var greetingText: some View {
        Text(greeting)
            .vessTextStyle(.label)
    }

    private var dateText: some View {
        Text(date, format: .dateTime.weekday(.wide).day().month(.wide))
            .vessTextStyle(.label)
    }
}

// MARK: - Meals

/// The step that comes next: the first main meal not yet logged, with its
/// usual time when there's enough history. Shown right under the day's
/// numbers so Today reads statement, evidence, then next step.
struct NextMealRow: View {
    let meal: MealType
    let history: [FoodLogEntry]
    let now: Date
    let calendar: Calendar
    let onAdd: () -> Void

    var body: some View {
        let usual = history.usualTime(for: meal, calendar: calendar)
            .flatMap { calendar.date(bySettingHour: $0.hour ?? 0, minute: $0.minute ?? 0, second: 0, of: now) }
        let shape = RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous)

        Button(action: onAdd) {
            HStack(spacing: VESSSpacing.sm) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VESSColor.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: VESSSpacing.xxs / 2) {
                    Text(meal.addTitle)
                        .vessTextStyle(.rowTitle)
                        .foregroundStyle(VESSColor.accent)
                    if let usual {
                        Text("Usually around \(usual, format: .dateTime.hour().minute())")
                            .vessTextStyle(.label)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, VESSSpacing.md)
            .padding(.vertical, VESSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: VESSHitTarget.control, alignment: .leading)
            .background(VESSColor.accentPale, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.addMeal")
    }
}

/// The day's meals so far, one row each, opening the Nutrition diary.
struct TodayMealsSection: View {
    let entries: [FoodLogEntry]
    let now: Date
    let onOpenDiary: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let logged = MealType.dayOrder.filter { !entries.entries(for: $0).isEmpty }

        VESSSection(header: VESSSectionHeader(title: "Meals", actionTitle: "Day diary", action: onOpenDiary)) {
            VESSRowGroup {
                ForEach(logged) { meal in
                    Button(action: onOpenDiary) {
                        loggedRow(meal, entries: entries.entries(for: meal))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loggedRow(_ meal: MealType, entries: [FoodLogEntry]) -> some View {
        VESSRow(
            title: Text(meal.title),
            subtitle: Text(entries.map(\.foodName).formatted(.list(type: .and, width: .narrow))),
            titleStyle: .rowTitle,
            subtitleLineLimit: 2
        ) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(VESSFormat.calories(entries.totalNutrition.calories)) kcal · \(entries.first?.loggedAt ?? now, format: .dateTime.hour().minute())")
                    .vessTextStyle(.label)
            } else {
                VStack(alignment: .trailing, spacing: VESSSpacing.xxs / 2) {
                    Text(VESSFormat.calories(entries.totalNutrition.calories))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(VESSColor.text)
                    if let first = entries.first {
                        Text(first.loggedAt, format: .dateTime.hour().minute())
                            .vessTextStyle(.label)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("\(VESSFormat.calories(entries.totalNutrition.calories)) kcal"))
        .accessibilityHint("Opens Nutrition")
    }
}

/// Water and, when there is one today, the workout: two quiet columns on one
/// surface, so they read as the day's other measures without competing with
/// the calories above.
struct DayMeasuresCard: View {
    let hydration: HydrationProgress
    let workout: Workout?
    let onAddWater: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VESSCard {
            if let workout, !dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: VESSSpacing.lg) {
                    WaterOverview(hydration: hydration, onAdd: onAddWater)
                    Rectangle()
                        .fill(VESSColor.divider)
                        .frame(width: 0.5)
                    ActivityOverview(workout: workout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                    WaterOverview(hydration: hydration, onAdd: onAddWater)
                    if let workout {
                        Rectangle()
                            .fill(VESSColor.divider)
                            .frame(height: 0.5)
                        ActivityOverview(workout: workout)
                    }
                }
            }
        }
    }
}

/// Water, open on the page. Shows the counted amount; when drinks count
/// only partly, the volume actually drunk is shown alongside it.
struct WaterOverview: View {
    let hydration: HydrationProgress
    let onAdd: () -> Void

    var body: some View {
        // One segment per 250 ml of target, within a readable range.
        let segments = min(max(Int((hydration.targetMilliliters / 250).rounded()), 4), 12)
        let countsPartly = (hydration.volumeMilliliters - hydration.consumedMilliliters) >= 10

        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSDotLabel(title: "Water", tint: VESSColor.water)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: VESSSpacing.md) {
                    metric
                    Spacer(minLength: 0)
                    addButton
                }
                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    metric
                    addButton
                }
            }

            VESSVesselLine(value: hydration.fractionComplete, tint: VESSColor.water, segments: segments)

            if countsPartly {
                // Milliliters, so the difference from the liter total stays visible.
                Text("\(VESSFormat.milliliters(hydration.consumedMilliliters)) ml counted from \(VESSFormat.milliliters(hydration.volumeMilliliters)) ml of drinks")
                    .vessTextStyle(.label)
            }
        }
    }

    private var metric: some View {
        VESSMetric(
            value: Text(VESSFormat.liters(fromMilliliters: hydration.consumedMilliliters)),
            context: Text("of \(VESSFormat.liters(fromMilliliters: hydration.targetMilliliters)) L"),
            style: .metric
        )
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water")
        .accessibilityValue(Text("\(VESSFormat.liters(fromMilliliters: hydration.consumedMilliliters)) of \(VESSFormat.liters(fromMilliliters: hydration.targetMilliliters)) liters"))
        .accessibilityIdentifier("today.water.value")
    }

    private var addButton: some View {
        Button("+250 ml", action: onAdd)
            .buttonStyle(.vessQuick)
            .fixedSize()
            .accessibilityLabel("Add 250 milliliters of water")
            .accessibilityIdentifier("today.water.add250")
    }
}

// MARK: - Activity

/// Today's workout. Steps are deliberately absent until Apple Health is
/// connected (Phase 7): VESS never shows invented step counts.
struct ActivityOverview: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSDotLabel(title: "Activity", tint: VESSColor.activity)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.md) {
                    Text(workout.name)
                        .vessTextStyle(.rowTitle)
                        .fixedSize()
                    Spacer(minLength: 0)
                    status
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text(workout.name)
                        .vessTextStyle(.rowTitle)
                    status
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        if workout.isCompleted {
            Label {
                Text(detail(prefix: "Done"))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(VESSColor.accent)
            }
            .font(.subheadline)
            .foregroundStyle(VESSColor.text)
        } else if let scheduled = workout.scheduledDate {
            Text("Planned · \(scheduled, format: .dateTime.hour().minute())")
                .vessTextStyle(.secondary)
        }
    }

    private func detail(prefix: LocalizedStringResource) -> String {
        guard let minutes = workout.durationMinutes else { return String(localized: prefix) }
        return String(localized: "\(String(localized: prefix)) · \(minutes) min")
    }
}

// MARK: - Expiring soon

struct ExpiringSoonSection: View {
    let items: [InventoryItem]
    let now: Date
    let calendar: Calendar

    var body: some View {
        VESSSection(header: VESSSectionHeader(
            title: "Expiring soon",
            detail: Text("^[\(items.count) item](inflect: true)")
        )) {
            VESSRowGroup {
                ForEach(items.prefix(3)) { item in
                    VESSRow(
                        title: Text(item.name),
                        subtitle: Text("\(Text(item.location.title)) · \(VESSFormat.quantity(item.quantity)) \(Text(item.unit.abbreviation))"),
                        trailing: { badge(for: item.expirationStatus(now: now, calendar: calendar)) }
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func badge(for status: ExpirationStatus) -> some View {
        switch status {
        case .expired:
            VESSTag(text: Text("Expired"), tone: .warning)
        case .today:
            VESSTag(text: Text("Today"), tone: .warning)
        case .tomorrow:
            VESSTag(text: Text("Tomorrow"), tone: .warning)
        case .soon(let days):
            VESSTag(text: Text("In \(days) days"))
        case .later, .noDate:
            EmptyView()
        }
    }
}
