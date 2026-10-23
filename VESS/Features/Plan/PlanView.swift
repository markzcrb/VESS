import SwiftUI

/// Plan: a week of meals (A01). Past days show what was logged (A10); today
/// and later show each main meal as eaten, planned or open. An empty future
/// week offers suggestions or a copy of this week (A09). Recipes are a
/// DEBUG-only segment until there is real recipe content.
struct PlanView: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Segment: Hashable { case week, recipes, grocery }

    @State private var segment: Segment = .week
    @State private var weekOffset = 0
    /// The day picked in the strip or the month grid (17, 18).
    @State private var selectedDay = Calendar.current.startOfDay(for: AppClock.now)
    @State private var showMonth = false
    @State private var monthOffset = 0
    /// Days whose empty "Nothing planned yet" row was opened to add a meal.
    @State private var expandedDays: Set<Date> = []
    @State private var scrollTarget: Date?
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                // A day picked in the strip or grid brings its section up.
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? nil : VESSMotion.selection) { proxy.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
            // Strip and grid days, arrows and swipes all move the selection.
            .vessHaptic(.selection, trigger: selectedDay)
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
            // The strip and grid sit right under their title, as in 17 and 18.
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                header(start: start, end: end, today: today)
                if showMonth {
                    PlanMonthGrid(
                        month: monthDate(today: today),
                        selection: selectedDay,
                        calendar: calendar,
                        store: store,
                        onSelect: select(fromMonth:)
                    )
                } else {
                    PlanWeekStrip(days: plan.days, selection: selectedDay, calendar: calendar) { day in
                        selectedDay = day
                        scrollTarget = day
                    } onSwipe: { change in
                        changeWeek(by: change)
                    }
                }
            }
            if showMonth {
                // The selected day's line replaces the week summary.
                if let day = selectedPlanDay {
                    Text("\(Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide))) · \(day.spokenStatus)")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                    let open = selectedWeek.openSlots.filter { calendar.isDate($0.day, inSameDayAs: day.date) }
                    if !open.isEmpty {
                        NavigationLink {
                            SuggestionsView(openSlots: open, plannedNames: Set(selectedWeek.days.flatMap { $0.slots.compactMap { if case .planned(let meal) = $0.slot { meal.name } else { nil } } }))
                        } label: {
                            Text("Suggest meals for ^[\(open.count) open slot](inflect: true)")
                        }
                        .buttonStyle(.vessPrimary)
                        .accessibilityIdentifier("plan.suggest")
                    }
                }
            } else if isPastWeek {
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

        if isEmptyFuture && !showMonth {
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

            if showMonth {
                // 18: only the selected day under the grid.
                if let day = selectedPlanDay {
                    daySection(day)
                }
            } else {
                #if DEBUG
                featuredRecipe(plan)
                #endif

                ForEach(plan.days, id: \.date) { day in
                    daySection(day)
                }
            }

            if !isPastWeek, !showMonth, let insight = insight(plan) {
                VESSInsightCard(text: insight, linkTitle: nil)
            }
        }
    }

    /// "19–25 October ˅" (tap for the month) or "October ˄", the Today
    /// chip when away from this week, and the arrows (week or month).
    @ViewBuilder
    private func header(start: Date, end: Date, today: Date) -> some View {
        let isAway = showMonth ? (monthOffset != 0 || !isInThisWeek(selectedDay, today: today)) : (weekOffset != 0 || !isInThisWeek(selectedDay, today: today))
        // At accessibility sizes the controls go under the title, so the
        // range never breaks mid-word. Otherwise they share a row while the
        // title fits at 80 % (the Today chip on a 402 pt screen) and drop
        // under it when it doesn't (SE), so the range is never cut.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                titleButton(start: start, end: end, today: today, wraps: true)
                headerControls(isAway: isAway, today: today)
            }
        } else {
            PlanHeaderLayout(spacing: VESSSpacing.sm, minimumScale: Self.titleMinimumScale) {
                titleButton(start: start, end: end, today: today, wraps: false)
                headerControls(isAway: isAway, today: today)
            }
        }
    }

    private static let titleMinimumScale: CGFloat = 0.8

    private func titleButton(start: Date, end: Date, today: Date, wraps: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : VESSMotion.selection) {
                if !showMonth {
                    monthOffset = calendar.dateComponents([.month], from: monthStart(today), to: monthStart(selectedDay)).month ?? 0
                }
                showMonth.toggle()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                Text(showMonth ? monthDate(today: today).formatted(.dateTime.month(.wide)) : rangeText(start: start, end: end))
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .lineLimit(wraps ? nil : 1)
                    .minimumScaleFactor(wraps ? 1 : Self.titleMinimumScale)
                    .fixedSize(horizontal: false, vertical: wraps)
                Image(systemName: showMonth ? "chevron.up" : "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VESSColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: VESSHitTarget.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint(showMonth ? "Closes the month" : "Opens the month")
        .accessibilityIdentifier("plan.title")
    }

    private func headerControls(isAway: Bool, today: Date) -> some View {
        HStack(spacing: VESSSpacing.xxs) {
            if isAway {
                Button("Today") { goToToday(today) }
                    .buttonStyle(.vessQuick)
                    .fixedSize()
                    .accessibilityIdentifier("plan.today")
            }
            VESSIconButton(systemImage: "chevron.left", label: showMonth ? "Previous month" : "Previous week") {
                if showMonth { monthOffset -= 1 } else { changeWeek(by: -1) }
            }
            .accessibilityIdentifier("plan.previousWeek")
            VESSIconButton(systemImage: "chevron.right", label: showMonth ? "Next month" : "Next week") {
                if showMonth { monthOffset += 1 } else { changeWeek(by: 1) }
            }
            .accessibilityIdentifier("plan.nextWeek")
        }
    }

    // MARK: Calendar

    private var selectedWeek: WeekPlan {
        PlanCalendarData(store: store, calendar: calendar).week(containing: selectedDay, now: AppClock.now)
    }

    private var selectedPlanDay: WeekPlan.Day? {
        selectedWeek.days.first { calendar.isDate($0.date, inSameDayAs: selectedDay) }
    }

    private func monthStart(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func monthDate(today: Date) -> Date {
        calendar.date(byAdding: .month, value: monthOffset, to: monthStart(today)) ?? today
    }

    private func isInThisWeek(_ day: Date, today: Date) -> Bool {
        calendar.isDate(day, equalTo: today, toGranularity: .weekOfYear)
    }

    /// Arrows and swipes: the week moves, and the selected day with it.
    private func changeWeek(by change: Int) {
        weekOffset += change
        selectedDay = calendar.date(byAdding: .day, value: 7 * change, to: selectedDay) ?? selectedDay
    }

    private func goToToday(_ today: Date) {
        withAnimation(reduceMotion ? nil : VESSMotion.selection) {
            weekOffset = 0
            monthOffset = 0
            selectedDay = today
            showMonth = false
        }
    }

    /// A day in the month grid: its week opens with it selected.
    private func select(fromMonth day: Date) {
        let thisWeek = calendar.startOfWeek(for: AppClock.now)
        // Both are week starts, so the day count is a whole number of weeks.
        let weeks = (calendar.dateComponents([.day], from: thisWeek, to: calendar.startOfWeek(for: day)).day ?? 0) / 7
        withAnimation(reduceMotion ? nil : VESSMotion.selection) {
            selectedDay = calendar.startOfDay(for: day)
            weekOffset = weeks
            showMonth = false
        }
        Task { @MainActor in scrollTarget = calendar.startOfDay(for: day) }
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
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDay)
        return VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            Group {
                if day.isToday {
                    Text("Today · \(Text(day.date, format: .dateTime.weekday(.wide).day().month(.abbreviated)))")
                } else {
                    Text(day.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                }
            }
            .vessTextStyle(.labelCaps)
            // The day picked in the strip stands out.
            .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
            .accessibilityAddTraits(.isHeader)

            VESSRowGroup {
                if day.isPast {
                    let eaten = day.slots.filter { if case .eaten = $0.slot { true } else { false } }
                    if eaten.isEmpty {
                        emptyRow(Text("Nothing logged"))
                    } else {
                        ForEach(eaten, id: \.meal) { slot in
                            slotRow(slot.meal, slot.slot, day: day)
                        }
                    }
                } else if day.filledCount == 0 && !expandedDays.contains(day.date) {
                    Button {
                        withAnimation(reduceMotion ? nil : VESSMotion.selection) { _ = expandedDays.insert(day.date) }
                    } label: {
                        emptyRow(Text("Nothing planned yet"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the meals to plan")
                } else {
                    ForEach(day.slots, id: \.meal) { slot in
                        slotRow(slot.meal, slot.slot, day: day)
                    }
                }
            }
            .vessHairlineBottom()
        }
        .id(day.date)
    }

    /// "Nothing logged", "Nothing planned yet": at the header's leading edge.
    private func emptyRow(_ text: Text) -> some View {
        text
            .vessTextStyle(.bodyM)
            .foregroundStyle(VESSColor.secondaryText)
            .frame(maxWidth: .infinity, minHeight: VESSSize.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// Eaten (check), planned (clock) and open (+) rows, as in 17.
    @ViewBuilder
    private func slotRow(_ meal: MealType, _ slot: WeekPlan.Slot, day: WeekPlan.Day) -> some View {
        switch slot {
        case .eaten(let entries):
            VESSListRow(
                systemImage: "checkmark",
                title: Text(MealSuggestions.Candidate.mealName(entries.map(\.foodName))),
                subtitle: Text("\(Text(meal.title)) · eaten"),
                value: Text("\(VESSFormat.calories(entries.totalNutrition.calories)) kcal"),
                showsChevron: false
            )
        case .planned(let plannedMeal):
            NavigationLink {
                PlannedMealView(mealID: plannedMeal.id)
            } label: {
                VESSListRow(
                    systemImage: "clock",
                    title: Text(plannedMeal.name),
                    subtitle: Text("\(Text(meal.title)) · planned"),
                    value: Text("\(VESSFormat.calories(plannedMeal.nutrition.calories)) kcal")
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.planned.\(plannedMeal.name)")
        case .open:
            NavigationLink {
                AddToSlotView(day: day.date, meal: meal)
            } label: {
                VESSListRow(systemImage: "plus", title: Text("Add \(String(localized: meal.title).localizedLowercase)"), subtitle: Text("\(Text(meal.title)) · open slot"))
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

/// The Plan title row: title and controls side by side while the title
/// fits at `minimumScale`, otherwise the controls go under the title.
private struct PlanHeaderLayout: Layout {
    let spacing: CGFloat
    let minimumScale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? subviews[0].sizeThatFits(.unspecified).width + spacing + subviews[1].sizeThatFits(.unspecified).width
        let controls = subviews[1].sizeThatFits(.unspecified)
        if fitsRow(width: width, subviews: subviews) {
            let title = subviews[0].sizeThatFits(ProposedViewSize(width: width - spacing - controls.width, height: nil))
            return CGSize(width: width, height: max(title.height, controls.height))
        }
        let title = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: title.height + spacing + controls.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let controls = subviews[1].sizeThatFits(.unspecified)
        if fitsRow(width: bounds.width, subviews: subviews) {
            let titleProposal = ProposedViewSize(width: bounds.width - spacing - controls.width, height: nil)
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: titleProposal)
            subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
        } else {
            let titleProposal = ProposedViewSize(width: bounds.width, height: nil)
            let title = subviews[0].sizeThatFits(titleProposal)
            subviews[0].place(at: bounds.origin, proposal: titleProposal)
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + title.height + spacing), proposal: .unspecified)
        }
    }

    private func fitsRow(width: CGFloat, subviews: Subviews) -> Bool {
        let title = subviews[0].sizeThatFits(.unspecified).width
        let controls = subviews[1].sizeThatFits(.unspecified).width
        return title * minimumScale + spacing + controls <= width
    }
}
