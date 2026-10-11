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
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                header
                portionPicker
                NutrientList(nutrition: nutrition)
                if !food.allergens.isEmpty {
                    Text("Contains \(food.allergens.sorted { $0.rawValue < $1.rawValue }.map { String(localized: $0.title) }.formatted(.list(type: .and)))")
                        .vessTextStyle(.secondary)
                }
                if food.source == .openFoodFacts {
                    attribution
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(VESSColor.card)
        .vessBottomAction { addBar }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { favoriteButton }
        }
        .onAppear { lookup.cache(food) }
        .vessErrorAlert(isPresented: $showError, retry: add)
        .vessKeyboardDoneButton()
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            Text(food.name)
                .vessTextStyle(.detailTitle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let brand = food.brand {
                Text(brand)
                    .vessTextStyle(.secondary)
            }
            Text(food.provenanceText)
                .vessTextStyle(.label)
        }
    }

    private var portionPicker: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            HStack(alignment: .bottom, spacing: VESSSpacing.sm) {
                VESSTextField("Amount", text: $countText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("foodDetail.amount")
                Menu {
                    Picker("Portion", selection: $option) {
                        ForEach(food.portionOptions) { option in
                            Text(label(for: option)).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: VESSSpacing.xxs) {
                        Text(label(for: option))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                    }
                    .font(.body)
                    .foregroundStyle(VESSColor.text)
                    .padding(.horizontal, VESSSpacing.md)
                    .frame(minHeight: VESSHitTarget.control)
                    .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
                }
                .accessibilityLabel(Text("Portion: \(label(for: option))"))
                .onChange(of: option) { old, new in
                    // Keep the amount sensible when switching between "1 slice" and grams.
                    if new.isBaseUnit != old.isBaseUnit, let count = VESSFormat.number(from: countText) {
                        let base = count * old.amount
                        countText = VESSFormat.quantity(new.isBaseUnit ? base : base / new.amount)
                    }
                }
            }
            if let portion {
                Text(portion.text(unit: food.servingUnit))
                    .vessTextStyle(.label)
            }
        }
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            Text(OpenFoodFactsClient.attribution)
                .vessTextStyle(.label)
                .fixedSize(horizontal: false, vertical: true)
            if let url = food.sourceInfo?.url {
                Link("View or correct this product on Open Food Facts", destination: url)
                    .font(.footnote)
                    .foregroundStyle(VESSColor.accent)
            }
        }
    }

    private var addBar: some View {
        VStack(spacing: VESSSpacing.xs) {
            if !food.nutrition.canBeLogged {
                Text("This product doesn't list calories, so it can't be logged. Create it as your own food instead.")
                    .vessTextStyle(.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: add) {
                Text("Add to \(Text(meal.title))")
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

    private func label(for option: ServingOption) -> String {
        if option.isBaseUnit { return String(localized: food.servingUnit.abbreviation) }
        return "\(option.label) (\(VESSFormat.quantity(option.amount)) \(String(localized: food.servingUnit.abbreviation)))"
    }

    private var logTime: Date {
        if calendar.isDateInToday(day) { return .now }
        let time = meal.typicalTime
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
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
