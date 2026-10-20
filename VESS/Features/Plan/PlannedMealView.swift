import SwiftUI

/// A03–A04: a planned meal. What it adds against the day's targets, its
/// ingredients against the pantry, and Move, Replace or Remove. Today's
/// meals can be logged from here ("Log as Dinner").
struct PlannedMealView: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss

    let mealID: UUID

    @State private var showMove = false
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if let meal = store.plannedMeal(id: mealID) {
                content(meal)
                    .vessDetailTitle(title(for: meal))
                    .sheet(isPresented: $showMove) {
                        MoveMealSheet(meal: meal, onMoved: { dismiss() })
                    }
            } else {
                Color.clear
            }
        }
        .vessScreenBackground()
        .vessErrorAlert(isPresented: $showError)
    }

    private func content(_ meal: PlannedMeal) -> some View {
        let now = AppClock.now
        let isToday = calendar.isDate(meal.day, inSameDayAs: now)
        let pantry = store.inventory
        let statuses = meal.items.map { PantryMatch.status(for: $0.name, in: pantry, now: now, calendar: calendar) }
        let toBuy = statuses.filter { $0 == .toBuy }.count

        return ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                // No food photo: VESS shows only the user's own photos.
                RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                    .fill(VESSColor.fill)
                    .frame(height: 120)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.title)
                            .foregroundStyle(VESSColor.decorative)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    Text(meal.name)
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(dayName(meal.day)) · \(Text(meal.mealType.title)) · \(time(for: meal), format: .dateTime.hour().minute())")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }

                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text(VESSFormat.calories(meal.nutrition.calories))
                        .vessTextStyle(.displayL)
                        .foregroundStyle(VESSColor.text)
                    Text("kcal")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .accessibilityElement(children: .combine)

                macros(meal)

                if isToday {
                    Button {
                        log(meal)
                    } label: {
                        Text("Log as \(Text(meal.mealType.title))")
                    }
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("plannedMeal.log")
                }

                if !meal.items.isEmpty {
                    VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                        VESSSectionHeader(title: "Ingredients", detail: toBuy > 0 ? Text("\(toBuy) to buy") : Text("All at home"))
                        VESSRowGroup {
                            ForEach(Array(zip(meal.items, statuses).enumerated()), id: \.offset) { _, pair in
                                VESSRow(title: Text(pair.0.name), subtitle: pair.1.text) {
                                    if let amount = pair.0.amountText {
                                        Text(amount)
                                            .vessTextStyle(.bodyM)
                                            .foregroundStyle(VESSColor.secondaryText)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .vessHairlineBottom()
                    }
                }

                #if DEBUG
                if case .recipe(let id) = meal.source, let recipe = PlanCandidates.recipe(id: id) {
                    NavigationLink("View recipe") { RecipeView(recipe: recipe) }
                        .buttonStyle(.vessSecondary)
                }
                #endif

                VStack(spacing: VESSSpacing.sm) {
                    Button("Move / change meal") { showMove = true }
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("plannedMeal.move")
                    NavigationLink("Replace meal") {
                        AddToSlotView(day: meal.day, meal: meal.mealType, replacing: meal)
                    }
                    .buttonStyle(.vessSecondary)
                    .accessibilityIdentifier("plannedMeal.replace")
                    Button("Remove from plan") { remove(meal) }
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("plannedMeal.remove")
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
    }

    private func macros(_ meal: PlannedMeal) -> some View {
        let targets = store.profile?.nutritionTargets
        return VStack(spacing: VESSSpacing.lg) {
            bar("Protein", .protein, meal.nutrition.proteinGrams, target: targets?.proteinGrams ?? 0, metric: .protein, meal: meal)
            bar("Carbs", .carbohydrates, meal.nutrition.carbohydrateGrams, target: targets?.carbohydrateGrams ?? 0, metric: .carbs, meal: meal)
            bar("Fat", .fat, meal.nutrition.fatGrams, target: targets?.fatGrams ?? 0, metric: .fat, meal: meal)
        }
    }

    private func bar(_ name: LocalizedStringResource, _ nutrient: CoreNutrient, _ grams: Double, target: Double, metric: VESSMetricKind, meal: PlannedMeal) -> some View {
        guard meal.nutrition.isReported(nutrient) else {
            return VESSMacroBar(name: name, value: String(localized: "Not reported"), target: "", adding: 0, metric: metric)
        }
        return VESSMacroBar(
            name: name,
            value: "\(VESSFormat.grams(grams)) g",
            target: target > 0 ? "/ \(VESSFormat.grams(target)) g" : "",
            adding: target > 0 ? grams / target : 0,
            metric: metric
        )
    }

    // MARK: Values

    /// "TONIGHT" for today's dinner, "TODAY", or the weekday.
    private func title(for meal: PlannedMeal) -> LocalizedStringResource {
        if calendar.isDate(meal.day, inSameDayAs: AppClock.now) {
            return meal.mealType == .dinner ? "Tonight" : "Today"
        }
        return "\(meal.day.formatted(.dateTime.weekday(.wide)))"
    }

    private func dayName(_ day: Date) -> Text {
        calendar.isDate(day, inSameDayAs: AppClock.now) ? Text("Today") : Text(day, format: .dateTime.weekday(.wide))
    }

    /// The user's usual time for the meal (14-day median), or its typical time.
    private func time(for meal: PlannedMeal) -> Date {
        let start = calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: meal.day) ?? meal.day
        let usual = store.foodEntries(from: start, to: calendar.startOfDay(for: AppClock.now))
            .usualTime(for: meal.mealType, calendar: calendar) ?? meal.mealType.typicalTime
        return calendar.date(bySettingHour: usual.hour ?? 12, minute: usual.minute ?? 0, second: 0, of: meal.day) ?? meal.day
    }

    // MARK: Actions

    private func log(_ meal: PlannedMeal) {
        do {
            try PlanLogging.log(meal, store: store, undo: undo, calendar: calendar)
            dismiss()
        } catch {
            showError = true
        }
    }

    private func remove(_ meal: PlannedMeal) {
        do {
            try store.deletePlannedMeal(id: meal.id)
            dismiss()
        } catch {
            showError = true
        }
    }
}
