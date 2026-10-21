import SwiftUI

/// Plan: a week of meals (A01). Past days show what was logged (A10); today
/// and later show each main meal as eaten, planned or open. An empty future
/// week offers suggestions or a copy of this week (A09). Recipes are a
/// DEBUG-only segment until there is real recipe content.
struct PlanView: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Segment: Hashable { case week, recipes, grocery }

    @State private var segment: Segment = .week
    @State private var weekOffset = 0
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.section) {
                    VESSSegmented(selection: $segment, options: segments)
                    switch segment {
                    case .week: week
                    case .recipes: recipes
                    case .grocery: GroceryContent(onPlanMeals: { segment = .week })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.xs)
                .padding(.bottom, VESSSpacing.huge)
            }
            .vessScreenBackground()
            .vessDetailTitle("Plan")
            .vessErrorAlert(isPresented: $showError)
        }
    }

    /// Recipes is a DEBUG-only segment until there is real recipe content.
    private var segments: [(value: Segment, title: LocalizedStringResource)] {
        #if DEBUG
        [(.week, "Week"), (.recipes, "Recipes"), (.grocery, "Grocery")]
        #else
        [(.week, "Week"), (.grocery, "Grocery")]
        #endif
    }

    // MARK: Week

    @ViewBuilder
    private var week: some View {
        let now = AppClock.now
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: calendar.startOfWeek(for: now)) ?? today
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let planned = store.plannedMeals(from: start, to: end)
        let plan = WeekPlan(weekStart: start, entries: store.foodEntries(from: start, to: end), planned: planned, now: now, calendar: calendar)
        let isPastWeek = end <= today
        let isEmptyFuture = start > today && plan.filledCount == 0

        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            header(start: start, end: end)
            if isPastWeek {
                pastSummary(plan)
            } else if isEmptyFuture {
                Text(weekOffset == 1 ? "Next week" : "Later")
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.text)
            } else {
                Text("\(plan.filledCount) of \(plan.slotCount) meals planned · ^[\(plan.openSlots.count) open slot](inflect: true)")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                if !plan.openSlots.isEmpty {
                    suggestLink(plan, planned: planned, title: "Suggest meals for ^[\(plan.openSlots.count) open slot](inflect: true)")
                }
            }
        }

        if isEmptyFuture {
            emptyWeek(plan, planned: planned, start: start)
        } else {
            VESSRowGroup {
                if !isPastWeek {
                    let toBuy = GroceryModel(store: store, calendar: calendar).list(now: now).toBuy.count
                    Button { segment = .grocery } label: {
                        VESSListRow(
                            systemImage: "cart",
                            title: Text("Grocery list"),
                            subtitle: toBuy == 0 ? Text("Nothing to buy") : Text("\(toBuy) to buy · kept in step with this plan")
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("plan.grocery")
                }
                NavigationLink {
                    PantryView()
                } label: {
                    let overview = PantryOverview(items: store.inventory, now: now, calendar: calendar)
                    VESSListRow(
                        systemImage: "refrigerator",
                        title: Text("Pantry"),
                        subtitle: overview.useSoon.isEmpty
                            ? Text("^[\(overview.totalCount) item](inflect: true) at home")
                            : Text("^[\(overview.totalCount) item](inflect: true) at home · \(overview.useSoon.count) to use soon")
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("plan.pantry")
            }
            .vessHairlineBottom()

            #if DEBUG
            featuredRecipe(plan)
            #endif

            ForEach(plan.days, id: \.date) { day in
                daySection(day)
            }

            if !isPastWeek, let insight = insight(plan) {
                VESSInsightCard(text: insight, linkTitle: nil)
            }
        }
    }

    private func header(start: Date, end: Date) -> some View {
        // At accessibility sizes the arrows go under the title, so the
        // range never breaks mid-word.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))

        return layout {
            Text(rangeText(start: start, end: end))
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: VESSSpacing.sm)
            }
            HStack(spacing: VESSSpacing.xxs) {
                VESSIconButton(systemImage: "chevron.left", label: "Previous week") { weekOffset -= 1 }
                    .accessibilityIdentifier("plan.previousWeek")
                VESSIconButton(systemImage: "chevron.right", label: "Next week") { weekOffset += 1 }
                    .accessibilityIdentifier("plan.nextWeek")
            }
        }
    }

    /// "5–11 October", or "28 Sep–4 Oct" across months.
    private func rangeText(start: Date, end: Date) -> String {
        let last = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        if calendar.isDate(start, equalTo: last, toGranularity: .month) {
            return "\(start.formatted(.dateTime.day()))–\(last.formatted(.dateTime.day().month(.wide)))"
        }
        return "\(start.formatted(.dateTime.day().month(.abbreviated)))–\(last.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// A10: "21 meals logged, about 1,771 kcal a day."
    private func pastSummary(_ plan: WeekPlan) -> some View {
        let loggedDays = plan.days.filter { !$0.logged.isEmpty }
        let meals = plan.days.reduce(0) { $0 + $1.slots.filter { if case .eaten = $0.slot { true } else { false } }.count }
        let average = loggedDays.isEmpty ? 0 : loggedDays.reduce(0) { $0 + $1.logged.totalNutrition.calories } / Double(loggedDays.count)
        return Text(meals == 0
                    ? "Nothing was logged this week."
                    : "^[\(meals) meal](inflect: true) logged, about \(VESSFormat.calories(average)) kcal a day.")
            .vessTextStyle(.bodyM)
            .foregroundStyle(VESSColor.secondaryText)
    }

    private func suggestLink(_ plan: WeekPlan, planned: [PlannedMeal], title: LocalizedStringResource) -> some View {
        NavigationLink {
            SuggestionsView(openSlots: plan.openSlots, plannedNames: Set(planned.map(\.name)))
        } label: {
            Text(title)
        }
        .buttonStyle(.vessPrimary)
        .accessibilityIdentifier("plan.suggest")
    }

    /// A09.
    private func emptyWeek(_ plan: WeekPlan, planned: [PlannedMeal], start: Date) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            Text("Nothing planned yet")
                .vessTextStyle(.titleL)
                .foregroundStyle(VESSColor.text)
            Text("Plan a few dinners and VESS builds the grocery list from them.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: VESSSpacing.sm) {
                suggestLink(plan, planned: planned, title: "Suggest meals for the week")
                Button("Copy this week's plan") { copyPreviousWeek(into: start) }
                    .buttonStyle(.vessSecondary)
                    .accessibilityIdentifier("plan.copyWeek")
            }
            .padding(.top, VESSSpacing.xs)
        }
        .padding(.top, VESSSpacing.huge)
    }

    // MARK: Days

    private func daySection(_ day: WeekPlan.Day) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            Group {
                if day.isToday {
                    Text("Today \(Text(day.date, format: .dateTime.day().month(.abbreviated)))")
                } else {
                    Text(day.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                }
            }
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.secondaryText)
            .accessibilityAddTraits(.isHeader)

            VESSRowGroup {
                if day.isPast {
                    pastRow(day)
                } else {
                    ForEach(day.slots, id: \.meal) { slot in
                        slotRow(slot.meal, slot.slot, day: day)
                    }
                }
            }
            .vessHairlineBottom()
        }
    }

    /// "3 meals logged · Eaten · 1,840 kcal".
    private func pastRow(_ day: WeekPlan.Day) -> some View {
        let meals = Set(day.logged.map(\.mealType)).count
        return VESSRow(
            title: meals == 0 ? Text("Nothing logged") : Text("^[\(meals) meal](inflect: true) logged"),
            subtitle: meals == 0 ? nil : Text("Eaten")
        ) {
            Image(systemName: "checkmark")
                .foregroundStyle(meals == 0 ? .clear : VESSColor.secondaryText)
                .frame(width: VESSSize.rowIcon)
                .accessibilityHidden(true)
        } trailing: {
            if meals > 0 {
                Text("\(VESSFormat.calories(day.logged.totalNutrition.calories)) kcal")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func slotRow(_ meal: MealType, _ slot: WeekPlan.Slot, day: WeekPlan.Day) -> some View {
        switch slot {
        case .eaten(let entries):
            VESSRow(
                title: Text(MealSuggestions.Candidate.mealName(entries.map(\.foodName))),
                subtitle: Text("\(Text(meal.title)) · eaten")
            ) {
                Text("\(VESSFormat.calories(entries.totalNutrition.calories)) kcal")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
        case .planned(let plannedMeal):
            NavigationLink {
                PlannedMealView(mealID: plannedMeal.id)
            } label: {
                VESSListRow(
                    title: Text(plannedMeal.name),
                    subtitle: Text(meal.title),
                    value: Text("\(VESSFormat.calories(plannedMeal.nutrition.calories)) kcal")
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.planned.\(plannedMeal.name)")
        case .open:
            NavigationLink {
                AddToSlotView(day: day.date, meal: meal)
            } label: {
                VESSListRow(title: Text("\(Text(meal.title)) · open"), value: Text("Add meal"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.open.\(day.date.formatted(.dateTime.weekday(.abbreviated))).\(meal.rawValue)")
        }
    }

    // MARK: Insight

    /// Facts only: the week's average, and a day that's light on protein.
    private func insight(_ plan: WeekPlan) -> Text? {
        guard let profile = store.profile else { return nil }
        let totals = plan.days.map { day -> (date: Date, nutrition: NutritionFacts, filled: Int, upcoming: Bool) in
            var facts: [NutritionFacts] = []
            var filled = 0
            for slot in day.slots {
                switch slot.slot {
                case .eaten(let entries): facts.append(entries.totalNutrition); filled += 1
                case .planned(let meal): facts.append(meal.nutrition); filled += 1
                case .open: break
                }
            }
            return (day.date, facts.total, filled, !day.isPast)
        }
        let counted = totals.filter { $0.filled > 0 }
        guard !counted.isEmpty, counted.contains(where: { $0.upcoming }) else { return nil }
        let kcal = counted.reduce(0) { $0 + $1.nutrition.calories } / Double(counted.count)
        let protein = counted.reduce(0) { $0 + $1.nutrition.proteinGrams } / Double(counted.count)
        // Non-breaking spaces keep each number with its unit.
        let average = Text("This week averages \(VESSFormat.calories(kcal))\u{00A0}kcal and \(VESSFormat.grams(protein))\u{00A0}g protein.")
        let light = counted
            .filter { $0.upcoming && $0.filled >= 2 && $0.nutrition.proteinGrams < profile.nutritionTargets.proteinGrams * 0.75 }
            .min { $0.nutrition.proteinGrams < $1.nutrition.proteinGrams }
        guard let light else { return average }
        return Text("\(average) \(Text(light.date, format: .dateTime.weekday(.wide))) is light on protein.")
    }

    // MARK: Recipes (DEBUG)

    @ViewBuilder
    private var recipes: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            Text("Demo recipes")
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
            Text("Debug builds only. Pescatarian and nut-free, from the design's examples.")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
            VESSRowGroup {
                ForEach(MockData.recipes) { recipe in
                    NavigationLink {
                        RecipeView(recipe: recipe)
                    } label: {
                        VESSListRow(
                            title: Text(recipe.name),
                            subtitle: Text("\(Text(recipe.mealType.title)) · \(recipe.minutes) min"),
                            value: Text("\(VESSFormat.calories(recipe.nutrition.calories)) kcal")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .vessHairlineBottom()
        }
        #endif
    }

    #if DEBUG
    /// 07's "Cook tonight" card, when tonight's dinner is a recipe.
    @ViewBuilder
    private func featuredRecipe(_ plan: WeekPlan) -> some View {
        if let today = plan.days.first(where: \.isToday),
           let dinner = today.slots.first(where: { $0.meal == .dinner }),
           case .planned(let meal) = dinner.slot,
           case .recipe(let id) = meal.source,
           let recipe = PlanCandidates.recipe(id: id) {
            let expiring = MealSuggestions.expiringUsed(
                by: .init(recipe: recipe), day: today.date, pantry: store.inventory, now: AppClock.now, calendar: calendar
            )
            NavigationLink {
                RecipeView(recipe: recipe)
            } label: {
                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    Text(expiring.isEmpty ? "Cook tonight" : "Cook tonight · uses what expires soon")
                        .vessTextStyle(.labelCapsS)
                        .foregroundStyle(VESSColor.warningText)
                    Text(recipe.name)
                        .vessTextStyle(.bodyMStrong)
                        .foregroundStyle(VESSColor.text)
                    if !expiring.isEmpty {
                        Text("Uses the \(expiring.map { $0.name.lowercased() }.formatted(.list(type: .and))) before \(expiring.count == 1 ? "it expires" : "they expire").")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(Image(systemName: "clock")) \(recipe.minutes) min   \(Image(systemName: "flame")) \(VESSFormat.calories(recipe.nutrition.calories)) kcal")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.secondaryText)
                        // Without the inline symbols' names ("clock", "flame").
                        .accessibilityLabel(Text("\(recipe.minutes) min, \(VESSFormat.calories(recipe.nutrition.calories)) kcal"))
                }
                .padding(VESSSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.featuredRecipe")
        }
    }
    #endif

    // MARK: Actions

    /// A09: copies last week's planned meals into this week's open slots.
    private func copyPreviousWeek(into start: Date) {
        guard let previous = calendar.date(byAdding: .day, value: -7, to: start) else { return }
        do {
            for meal in store.plannedMeals(from: previous, to: start) {
                guard let day = calendar.date(byAdding: .day, value: 7, to: meal.day) else { continue }
                let copy = PlannedMeal(
                    id: UUID(), day: day, mealType: meal.mealType, name: meal.name, nutrition: meal.nutrition,
                    items: meal.items, source: meal.source, loggedAt: nil, createdAt: AppClock.now
                )
                try store.save(copy)
            }
        } catch {
            showError = true
        }
    }
}

#Preview("Plan") {
    PlanView()
        .previewEnvironment(LocalStore.preview())
}
