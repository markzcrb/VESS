import SwiftUI

/// Nutrition: the day diary. One day at a time, meal by meal, then drinks.
struct NutritionView: View {
    @Environment(LocalStore.self) private var store
    @State private var selectedDay = Date.now
    @State private var addFood: AddFoodRequest?
    @State private var addDrinkDay: Date?
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            if let profile = store.profile {
                content(profile: profile, now: .now)
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

        return VESSScreen(title: "Nutrition") {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VESSDayStrip(
                    days: week,
                    selection: $selectedDay,
                    today: now,
                    calendar: calendar,
                    hasEntries: { loggedDays.contains(calendar.startOfDay(for: $0)) }
                )
                CaloriesOverview(summary: summary, prominence: .compact)
            }

            if entries.isEmpty && drinks.isEmpty {
                // An empty day: one sentence, then the day's diary as a short
                // list where every meal is one tap from logging.
                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    Text(calendar.isDateInToday(selectedDay)
                         ? "Nothing logged yet today."
                         : "Nothing was logged on this day.")
                        .vessTextStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    EmptyDiaryList(
                        onAddFood: { meal in addFood = AddFoodRequest(meal: meal, day: selectedDay) },
                        onAddDrink: { addDrinkDay = selectedDay }
                    )
                }
            } else {
                // Meals and drinks sit closer together than top-level sections:
                // they are one diary, read top to bottom.
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    ForEach(MealType.dayOrder) { meal in
                        MealDiarySection(
                            meal: meal,
                            entries: entries.entries(for: meal),
                            onAdd: { addFood = AddFoodRequest(meal: meal, day: selectedDay) },
                            onDelete: { delete(entry: $0) }
                        )
                    }

                    DrinksDiarySection(
                        logs: drinks,
                        onAdd: { addDrinkDay = selectedDay },
                        onDelete: { delete(log: $0) }
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add food", systemImage: "plus") {
                    addFood = AddFoodRequest(meal: .likely(at: now, calendar: calendar), day: selectedDay)
                }
                .accessibilityIdentifier("nutrition.addFood")
            }
        }
        .sheet(item: $addFood) { request in
            AddFoodSheet(request: request)
        }
        .sheet(item: Binding(
            get: { addDrinkDay.map(DrinkSheetDay.init) },
            set: { addDrinkDay = $0?.day }
        )) { item in
            AddDrinkSheet(day: item.day)
        }
        .vessErrorAlert(isPresented: $showError)
    }

    // MARK: Helpers

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
        do { try store.deleteFoodEntry(id: entry.id) } catch { showError = true }
    }

    private func delete(log: HydrationLog) {
        do { try store.deleteHydrationLog(id: log.id) } catch { showError = true }
    }
}

/// Identifies a drink sheet presentation for a given day.
private struct DrinkSheetDay: Identifiable {
    let day: Date
    var id: Date { day }
}

#Preview("Sample day") {
    NutritionView()
        .environment(LocalStore.preview())
}

#Preview("Empty day") {
    NutritionView()
        .environment(LocalStore.preview(.profileOnly))
}

#Preview("Sample day, dark") {
    NutritionView()
        .environment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
