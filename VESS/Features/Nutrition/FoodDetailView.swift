import SwiftUI

/// A food's details: where its data comes from, a portion to log, and the
/// resulting nutrition. Pushed inside `FoodSearchSheet`.
struct FoodDetailView: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLookupService.self) private var lookup

    let food: Food
    let day: Date
    @Binding var meal: MealType
    let onLogged: () -> Void

    @State private var option: ServingOption
    @State private var countText: String
    @State private var showError = false
    @FocusState private var isAmountFocused: Bool

    private let calendar = Calendar.current

    init(food: Food, day: Date, meal: Binding<MealType>, onLogged: @escaping () -> Void) {
        self.food = food
        self.day = day
        self._meal = meal
        self.onLogged = onLogged
        let portion = food.defaultPortion
        _option = State(initialValue: portion.option)
        _countText = State(initialValue: VESSFormat.quantity(portion.count))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                header
                macros
                serving
                details
                if !food.allergens.isEmpty {
                    Text("Contains \(food.allergens.sorted { $0.rawValue < $1.rawValue }.map { String(localized: $0.title) }.formatted(.list(type: .and)))")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                if food.source == .openFoodFacts {
                    attribution
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .vessScreenBackground(.energy)
        .vessBottomAction(background: VESSColor.background) { addBar }
        .vessDetailTitle("Food")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { favoriteButton }
        }
        .onAppear { lookup.cache(food) }
        .vessErrorAlert(isPresented: $showError, retry: add)
        .vessKeyboardDoneButton()
    }

    // MARK: Sections

    /// Brand kicker, name, where the data comes from, and the big kcal.
    private var header: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                if let brand = food.brand {
                    Text(brand)
                        .vessTextStyle(.labelCapsS)
                        .foregroundStyle(VESSColor.tertiaryText)
                }
                Text(food.name)
                    .vessTextStyle(.titleL)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                // The honest source, never "verified".
                Text(food.provenanceText)
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
            }
            if nutrition.isReported(.calories) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text(VESSFormat.calories(nutrition.calories))
                        .vessTextStyle(.displayL)
                        .foregroundStyle(VESSColor.text)
                        .contentTransition(.numericText())
                    Text("kcal · \(amountText)")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Calories not reported")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
    }

    /// Grey is what's logged on this day; the hue is what this portion adds.
    private var macros: some View {
        let logged = store.foodEntries(on: day, calendar: calendar).totalNutrition
        let targets = store.profile?.nutritionTargets
        return VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            macroBar("Protein", .protein, adding: nutrition.proteinGrams, logged: logged.proteinGrams, target: targets?.proteinGrams ?? 0, metric: .protein)
            macroBar("Carbs", .carbohydrates, adding: nutrition.carbohydrateGrams, logged: logged.carbohydrateGrams, target: targets?.carbohydrateGrams ?? 0, metric: .carbs)
            macroBar("Fat", .fat, adding: nutrition.fatGrams, logged: logged.fatGrams, target: targets?.fatGrams ?? 0, metric: .fat)
            Text(calendar.isDateInToday(day)
                 ? "Grey is what you've logged today. Colour is what this adds."
                 : "Grey is what you logged that day. Colour is what this adds.")
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, VESSSpacing.xs)
        }
    }

    private func macroBar(
        _ name: LocalizedStringResource,
        _ nutrient: CoreNutrient,
        adding: Double,
        logged: Double,
        target: Double,
        metric: VESSMetricKind
    ) -> some View {
        guard nutrition.isReported(nutrient) else {
            return VESSMacroBar(name: name, value: String(localized: "Not reported"), target: "", logged: target > 0 ? logged / target : 0, adding: 0, metric: metric)
        }
        let total = "\(VESSFormat.grams(logged + adding))"
        return VESSMacroBar(
            name: name,
            value: "+\(VESSFormat.grams(adding)) g",
            target: target > 0 ? "→ \(total) / \(VESSFormat.grams(target)) g" : "→ \(total) g",
            logged: target > 0 ? logged / target : 0,
            adding: target > 0 ? adding / target : 0,
            metric: metric
        )
    }

    /// Serving chips, then the amount with − and +.
    private var serving: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Serving")
            VESSChipFlow {
                ForEach(servingChoices) { choice in
                    VESSChip(title: choice.title, isSelected: selectedChoice == choice) {
                        select(choice)
                    }
                }
                VESSChip(title: "Custom", isSelected: selectedChoice == nil) {
                    selectCustom()
                }
            }

            HStack(spacing: VESSSpacing.md) {
                VESSIconButton(systemImage: "minus", label: "Less") { step(by: -1) }
                    .disabled((portion?.count ?? 0) <= stepSize)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xxs) {
                    // No placeholder, so the field is as wide as the number.
                    TextField(text: $countText) { EmptyView() }
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .vessTextStyle(.displayM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize()
                        .focused($isAmountFocused)
                        .accessibilityLabel(Text("Amount in \(Text(unitLabel))"))
                        .accessibilityIdentifier("foodDetail.amount")
                    Text(unitLabel)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                Spacer(minLength: 0)
                VESSIconButton(systemImage: "plus", label: "More") { step(by: 1) }
            }
            if let portion, !portion.option.isBaseUnit {
                Text(portion.text(unit: food.servingUnit))
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// "Logged as Dinner · 19:30", "Per 100 g", then any extra nutrients.
    private var details: some View {
        VESSRowGroup {
            Menu {
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.dayOrder) { meal in
                        Text(meal.title).tag(meal)
                    }
                }
            } label: {
                VESSListRow(
                    systemImage: "clock",
                    title: Text("Logged as"),
                    value: Text("\(Text(meal.title)) · \(logTime, format: .dateTime.hour().minute())")
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mealPicker")

            if let per100 {
                VESSListRow(systemImage: "info.circle", title: Text(per100.title), value: per100.value, showsChevron: false)
            }
            if let fiber = nutrition.fiberGrams {
                VESSListRow(title: Text("Fiber"), value: Text("\(VESSFormat.quantity(fiber)) g"), showsChevron: false)
            }
            if let sugar = nutrition.sugarGrams {
                VESSListRow(title: Text("Sugars"), value: Text("\(VESSFormat.quantity(sugar)) g"), showsChevron: false)
            }
            if let sodium = nutrition.sodiumMilligrams {
                VESSListRow(title: Text("Sodium"), value: Text("\(VESSFormat.milliliters(sodium)) mg"), showsChevron: false)
            }
        }
        .vessHairlineBottom()
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            Text(OpenFoodFactsClient.attribution)
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let url = food.sourceInfo?.url {
                Link("View or correct this product on Open Food Facts", destination: url)
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.accent)
            }
        }
    }

    private var addBar: some View {
        VStack(spacing: VESSSpacing.xs) {
            if !food.nutrition.canBeLogged {
                Text("This product doesn't list calories, so it can't be logged. Create it as your own food instead.")
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: add) {
                if portion != nil, food.nutrition.canBeLogged {
                    Text("\(Text(meal.addToTitle)) · \(VESSFormat.calories(nutrition.calories)) kcal")
                } else {
                    Text(meal.addToTitle)
                }
            }
            .buttonStyle(.vessPrimary)
            .disabled(portion == nil || !food.nutrition.canBeLogged)
            .accessibilityIdentifier("foodDetail.add")
        }
    }

    private var favoriteButton: some View {
        let isFavorite = store.favoriteFoodIDs().contains(food.id)
        return Button {
            try? store.setFavorite(!isFavorite, for: food)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
        }
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        .accessibilityIdentifier("foodDetail.favorite")
        .sensoryFeedback(.selection, trigger: isFavorite)
    }

    // MARK: Values

    private var portion: Portion? {
        guard let count = VESSFormat.number(from: countText), count > 0, count <= 10_000 else { return nil }
        return Portion(option: option, count: count)
    }

    private var nutrition: NutritionFacts {
        food.nutrition(forQuantity: (portion ?? food.defaultPortion).baseAmount)
    }

    /// "150 g" or "1 cup (198 g)": the amount the kcal refers to.
    private var amountText: String {
        (portion ?? food.defaultPortion).text(unit: food.servingUnit)
    }

    private var unitLabel: String {
        option.isBaseUnit
            ? String(localized: food.servingUnit.abbreviation)
            : "× \(option.label)"
    }

    /// One serving chip: a named portion ("1 fillet") or a round base amount ("100 g").
    private struct ServingChoice: Identifiable, Equatable {
        let option: ServingOption
        let count: Double
        let title: LocalizedStringResource
        var id: String { "\(option.id)|\(count)" }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    private var servingChoices: [ServingChoice] {
        var choices = (food.servingOptions ?? []).map {
            ServingChoice(option: $0, count: 1, title: "\($0.label)")
        }
        // "100 g" for foods measured in grams or millilitres.
        if [.gram, .milliliter].contains(food.servingUnit) {
            let base = ServingOption.baseUnit(food.servingUnit)
            let abbreviation = String(localized: food.servingUnit.abbreviation)
            choices.insert(ServingChoice(option: base, count: 100, title: "100 \(abbreviation)"), at: 0)
            if food.servingOptions?.isEmpty ?? true, food.servingSize > 0, food.servingSize != 100 {
                choices.append(ServingChoice(option: base, count: food.servingSize, title: "\(VESSFormat.quantity(food.servingSize)) \(abbreviation)"))
            }
        }
        return choices
    }

    /// The chip matching the current amount, or `nil` for Custom.
    private var selectedChoice: ServingChoice? {
        guard let portion else { return nil }
        return servingChoices.first { $0.option == portion.option && $0.count == portion.count }
    }

    private func select(_ choice: ServingChoice) {
        option = choice.option
        countText = VESSFormat.quantity(choice.count)
        isAmountFocused = false
    }

    /// Custom: the amount in the base unit, ready to type.
    private func selectCustom() {
        let base = (portion ?? food.defaultPortion).baseAmount
        option = .baseUnit(food.servingUnit)
        countText = VESSFormat.quantity(base)
        isAmountFocused = true
    }

    /// 10 g or ml at a time, or half a named portion.
    private var stepSize: Double {
        option.isBaseUnit ? ([.gram, .milliliter].contains(food.servingUnit) ? 10 : 1) : 0.5
    }

    private func step(by direction: Double) {
        let current = portion?.count ?? 0
        let next = max(stepSize, (current / stepSize).rounded() * stepSize + direction * stepSize)
        countText = VESSFormat.quantity(min(next, 10_000))
    }

    /// Per 100 g or ml, for foods measured that way.
    private var per100: (title: LocalizedStringResource, value: Text)? {
        guard [.gram, .milliliter].contains(food.servingUnit), food.nutrition.isReported(.calories) else { return nil }
        let facts = food.nutrition(forQuantity: 100)
        let title: LocalizedStringResource = "Per 100 \(String(localized: food.servingUnit.abbreviation))"
        guard facts.isReported(.protein) else {
            return (title, Text("\(VESSFormat.calories(facts.calories)) kcal"))
        }
        return (title, Text("\(VESSFormat.calories(facts.calories)) kcal · \(VESSFormat.quantity(facts.proteinGrams)) g protein"))
    }

    private var logTime: Date {
        meal.logTime(on: day, calendar: calendar)
    }

    private func add() {
        guard let profile = store.profile, let portion, food.nutrition.canBeLogged else { return }
        let entry = FoodLogEntry(userID: profile.id, food: food, portion: portion, mealType: meal, loggedAt: logTime)
        do {
            try store.add(entry)
            lookup.cache(food)
            onLogged()
        } catch {
            showError = true
        }
    }
}
