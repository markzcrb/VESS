import SwiftUI

/// Nutrition: the day diary. One day at a time, meal by meal, then drinks.
struct NutritionView: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.vessHaptics) private var haptics
    @State private var selectedDay = AppClock.now
    @State private var addFood: AddFoodRequest?
    @State private var editing: FoodLogEntry?
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            if let profile = store.profile {
                content(profile: profile, now: AppClock.now)
            }
        }
    }

    private func content(profile: UserProfile, now: Date) -> some View {
        let entries = store.foodEntries(on: selectedDay, calendar: calendar)
        let drinks = store.hydrationLogs(on: selectedDay, calendar: calendar)
        let summary = DaySummary(
            entries: entries,
            hydrationLogs: drinks,
            targets: profile.nutritionTargets,
            waterTargetMilliliters: profile.waterTargetMilliliters,
            day: selectedDay,
            now: now,
            calendar: calendar
        )
        let week = weekDays(containing: selectedDay)
        let loggedDays = daysWithLogs(in: week)

        return ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    VESSDayStrip(
                        days: week,
                        selection: $selectedDay,
                        today: now,
                        calendar: calendar,
                        hasEntries: { loggedDays.contains(calendar.startOfDay(for: $0)) }
                    )
                    Text(editorialLine(isEmpty: entries.isEmpty && drinks.isEmpty))
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    DiaryTotals(summary: summary)
                }

                ForEach(MealType.dayOrder) { meal in
                    MealDiarySection(
                        meal: meal,
                        entries: entries.entries(for: meal),
                        emptyNote: emptyNote(for: meal, summary: summary, now: now),
                        onAdd: { addFood = AddFoodRequest(meal: meal, day: selectedDay) },
                        onEdit: { editing = $0 },
                        onDelete: { delete(entry: $0) }
                    )
                }

                DrinksDiarySection(
                    day: selectedDay,
                    logs: drinks,
                    onAdd: { addFood = AddFoodRequest(meal: .likely(at: AppClock.now, calendar: calendar), day: selectedDay, type: .drink) },
                    onDelete: { delete(log: $0) }
                )

                // Shortcuts into the Add sheet's saved foods.
                VESSChipFlow {
                    VESSChip(title: "Favorites", isSelected: false) {
                        addFood = AddFoodRequest(meal: .likely(at: now, calendar: calendar), day: selectedDay, collection: .favorites)
                    }
                    .accessibilityIdentifier("nutrition.favorites")
                    VESSChip(title: "My foods", isSelected: false) {
                        addFood = AddFoodRequest(meal: .likely(at: now, calendar: calendar), day: selectedDay, collection: .mine)
                    }
                    .accessibilityIdentifier("nutrition.myFoods")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground()
        .vessTabBarFade()
        .vessDetailTitle("Nutrition")
        .sheet(item: $addFood) { request in
            AddSheet(request: request)
        }
        .sheet(item: $editing) { entry in
            EditEntrySheet(entry: entry)
        }
        .vessErrorAlert(isPresented: $showError)
    }

    // MARK: Helpers

    private func editorialLine(isEmpty: Bool) -> LocalizedStringResource {
        guard isEmpty else { return "Your day, item by item." }
        return calendar.isDate(selectedDay, inSameDayAs: AppClock.now) ? "Nothing logged yet today." : "Nothing was logged on this day."
    }

    /// "Usually around 19:30 · 560 kcal left", for a meal not yet logged
    /// today. The usual time is the median of the last 14 days (at least 3).
    private func emptyNote(for meal: MealType, summary: DaySummary, now: Date) -> Text? {
        let end = calendar.startOfDay(for: now)
        guard calendar.isDate(selectedDay, inSameDayAs: now),
              let start = calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: end),
              let usual = store.foodEntries(from: start, to: end).usualTime(for: meal, calendar: calendar),
              let time = calendar.date(bySettingHour: usual.hour ?? 0, minute: usual.minute ?? 0, second: 0, of: now)
        else { return nil }
        let usually = Text("Usually around \(time, format: .dateTime.hour().minute())")
        let remaining = summary.caloriesRemaining
        guard summary.targets.calories > 0, remaining > 0 else { return usually }
        return Text("\(usually) · \(VESSFormat.calories(remaining)) kcal left")
    }

    private func weekDays(containing day: Date) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func daysWithLogs(in week: [Date]) -> Set<Date> {
        guard let first = week.first, let last = week.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        let start = calendar.startOfDay(for: first)
        let foodDays = store.foodEntries(from: start, to: end).map { calendar.startOfDay(for: $0.loggedAt) }
        let drinkDays = store.hydrationLogs(from: start, to: end).map { calendar.startOfDay(for: $0.loggedAt) }
        return Set(foodDays + drinkDays)
    }

    private func delete(entry: FoodLogEntry) {
        do { try store.deleteFoodEntry(id: entry.id); haptics.play(.warning) } catch { showError = true }
    }

    private func delete(log: HydrationLog) {
        do { try store.deleteHydrationLog(id: log.id); haptics.play(.warning) } catch { showError = true }
    }
}

#if DEBUG
#Preview("Sample day") {
    NutritionView()
        .previewEnvironment(LocalStore.preview())
}

#Preview("Empty day") {
    NutritionView()
        .previewEnvironment(LocalStore.preview(.profileOnly))
}

#Preview("Sample day, dark") {
    NutritionView()
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
#endif
