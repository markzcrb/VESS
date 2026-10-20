import SwiftUI

/// A request to open the food sheet for a meal on a day.
struct AddFoodRequest: Identifiable {
    let id = UUID()
    var meal: MealType
    var day: Date
    /// Which saved foods the Add sheet opens on.
    var collection: FoodCollection = .recent
}

/// H01–H03, manual entry: log a food from its label or a best guess,
/// without a product. Shown inside `FoodSearchSheet`. A macro left empty is
/// saved as "not reported", never as zero. Optionally saved to My foods.
struct QuickAddForm: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let day: Date
    @Binding var meal: MealType
    let onLogged: () -> Void

    @State private var name = ""
    @State private var servings = "1"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var saveToMyFoods = true
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                Text("A label, or your best guess.")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)

                VESSTextField("Food", text: $name, error: nameError)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("addFood.name")

                VESSTextField("Serving", text: $servings, unit: "serving", error: servingsError)
                    .keyboardType(.decimalPad)

                VESSTextField("Calories", text: $calories, unit: "kcal", error: caloriesError)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("addFood.calories")

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Protein, carbs, fat · optional")
                    macroFields
                    Text("Leave one empty if you don't know it. It shows as not reported, not as zero.")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VESSRowGroup {
                    Toggle(isOn: $saveToMyFoods) {
                        Text("Save to My foods")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.text)
                    }
                    .tint(VESSColor.accentFill)
                    .frame(minHeight: VESSSize.rowHeight)
                    .accessibilityIdentifier("addFood.saveToMyFoods")

                    Menu {
                        Picker("Meal", selection: $meal) {
                            ForEach(MealType.dayOrder) { meal in
                                Text(meal.title).tag(meal)
                            }
                        }
                    } label: {
                        VESSListRow(
                            title: Text("Adding to \(Text(meal.title))"),
                            value: Text(logTime, format: .dateTime.hour().minute())
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mealPicker")
                }
                .vessHairlineBottom()
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .vessScreenBackground()
        .vessBottomAction(background: VESSColor.background) {
            Button(action: add) {
                Text(meal.addToTitle)
            }
            .buttonStyle(.vessPrimary)
            .disabled(nutrition == nil)
            .accessibilityIdentifier("addFood.submit")
        }
        .vessDetailTitle("Manual entry")
        .vessErrorAlert(isPresented: $showError, retry: add)
        .vessKeyboardDoneButton()
    }

    private var macroFields: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: VESSSpacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: VESSSpacing.sm))
        return layout {
            VESSTextField("Protein", text: $protein, unit: "g", error: NutrientInput.grams(protein) == nil ? Text("0–1,000 g") : nil)
                .keyboardType(.decimalPad)
            VESSTextField("Carbs", text: $carbs, unit: "g", error: NutrientInput.grams(carbs) == nil ? Text("0–1,000 g") : nil)
                .keyboardType(.decimalPad)
            VESSTextField("Fat", text: $fat, unit: "g", error: NutrientInput.grams(fat) == nil ? Text("0–1,000 g") : nil)
                .keyboardType(.decimalPad)
        }
    }

    // MARK: Validation (H03)

    /// A required field only complains once a field below it has content,
    /// so an empty form (H01) stays calm and typing top to bottom never
    /// shows an error for the field you're about to fill (H03).
    private func hasContent(_ texts: [String]) -> Bool {
        texts.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var servingCount: Double? {
        guard let value = VESSFormat.number(from: servings), value > 0, value <= 100 else { return nil }
        return value
    }

    private var kcal: Double? {
        guard let value = VESSFormat.number(from: calories), (0...5000).contains(value) else { return nil }
        return value
    }

    private var nameError: Text? {
        hasContent([calories, protein, carbs, fat]) && trimmedName.isEmpty ? Text("Add a name so you can find it again.") : nil
    }

    private var servingsError: Text? {
        servingCount == nil ? Text("Enter a number of servings, up to 100.") : nil
    }

    private var caloriesError: Text? {
        if calories.trimmingCharacters(in: .whitespaces).isEmpty {
            return hasContent([protein, carbs, fat]) ? Text("Add calories to save.") : nil
        }
        return kcal == nil ? Text("Enter between 0 and 5,000 kcal.") : nil
    }

    /// Nutrition for one serving, or `nil` while the form is incomplete or invalid.
    private var nutrition: NutritionFacts? {
        guard !trimmedName.isEmpty, servingCount != nil, let kcal,
              let proteinGrams = NutrientInput.grams(protein),
              let carbGrams = NutrientInput.grams(carbs),
              let fatGrams = NutrientInput.grams(fat)
        else { return nil }
        return NutrientInput.facts(calories: kcal, protein: proteinGrams, carbs: carbGrams, fat: fatGrams)
    }

    /// Now for today; the meal's typical time for a past day.
    private var logTime: Date {
        meal.logTime(on: day, calendar: calendar)
    }

    /// Logs the entry. With "Save to My foods", the food is saved first and
    /// the entry refers to it, so it can be found and logged again.
    private func add() {
        guard let profile = store.profile, let nutrition, let count = servingCount else { return }
        do {
            if saveToMyFoods {
                let food = Food(
                    id: UUID(), name: trimmedName, brand: nil, barcode: nil,
                    servingSize: 1, servingUnit: .serving, nutrition: nutrition,
                    ingredients: [], allergens: [], quality: nil, source: .userCreated,
                    createdAt: AppClock.now, updatedAt: AppClock.now
                )
                try store.save(food)
                let portion = Portion(option: .baseUnit(.serving), count: count)
                try store.add(FoodLogEntry(userID: profile.id, food: food, portion: portion, mealType: meal, loggedAt: logTime))
            } else {
                try store.add(FoodLogEntry(
                    id: UUID(), userID: profile.id, foodID: nil, foodName: trimmedName, mealType: meal,
                    quantity: count, servingUnit: .serving, nutrition: nutrition.scaled(by: count),
                    loggedAt: logTime, source: .userCreated
                ))
            }
            onLogged()
        } catch {
            showError = true
        }
    }
}

/// Parsing for nutrient fields where empty means "not reported".
enum NutrientInput {
    /// `.some(nil)` for an empty field (unreported), `.some(value)` for a
    /// plausible gram amount, `nil` for invalid input.
    static func grams(_ text: String) -> Double?? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .some(nil) }
        guard let value = VESSFormat.number(from: text), (0...1000).contains(value) else { return nil }
        return .some(value)
    }

    /// Builds nutrition facts, marking empty macros as unreported.
    static func facts(calories: Double, protein: Double?, carbs: Double?, fat: Double?) -> NutritionFacts {
        var unreported = Set<CoreNutrient>()
        if protein == nil { unreported.insert(.protein) }
        if carbs == nil { unreported.insert(.carbohydrates) }
        if fat == nil { unreported.insert(.fat) }
        return NutritionFacts(
            calories: calories,
            proteinGrams: protein ?? 0,
            carbohydrateGrams: carbs ?? 0,
            fatGrams: fat ?? 0,
            unreportedCoreNutrients: unreported.isEmpty ? nil : unreported
        )
    }
}
