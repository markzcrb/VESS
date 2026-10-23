import SwiftUI

/// A request to open the Add sheet (21) for a meal on a day.
struct AddFoodRequest: Identifiable {
    let id = UUID()
    var meal: MealType
    var day: Date
    /// Which saved foods Food opens on.
    var collection: FoodCollection = .recent
    /// The type an entry point asks for (Add drink, Habits +, …); `nil`
    /// opens on Food, or on the type used last within the past hour.
    var type: AddType?
}

/// H01–H03, manual entry: log a food from its label or a best guess,
/// without a product. Quick add in the Add sheet. A macro left empty is
/// saved as "not reported", never as zero. Optionally saved to My foods.
struct QuickAddForm: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let day: Date
    @Binding var meal: MealType
    /// Inside the Add sheet (21), which has its own title and X.
    var embedded = false
    let onLogged: () -> Void

    @State private var name = ""
    @State private var servings = "1"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var saveToMyFoods = true
    @State private var showError = false
    /// The field to bring into view once the keyboard is up.
    @State private var focusedField: Field?

    private enum Field: Hashable { case name, servings, calories, protein, carbs, fat }

    private let calendar = Calendar.current

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                // The editorial line belongs to the standalone screen.
                if !embedded {
                    Text("A label, or your best guess.")
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VESSTextField("Food", text: $name, error: nameError) { focusedField = .name }
                    .id(Field.name)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("addFood.name")

                VESSTextField("Serving", text: $servings, unit: "serving", error: servingsError) { focusedField = .servings }
                    .id(Field.servings)
                    .keyboardType(.decimalPad)

                VESSTextField("Calories", text: $calories, unit: "kcal", error: caloriesError) { focusedField = .calories }
                    .id(Field.calories)
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("addFood.calories")

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Macros · optional")
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
                    .toggleStyle(.vess)
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
            .vessContentTop(VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        // Wait for the keyboard to finish appearing, then centre the field
        // in what's left of the screen (small iPhones and AX sizes too).
        .task(id: focusedField) {
            guard let field = focusedField else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(field, anchor: .center) }
        }
        }
        .vessScreenBackground()
        .vessBottomAction(background: VESSColor.background) {
            Button(action: add) {
                Text(meal.addToTitle)
            }
            .buttonStyle(.vessPrimary)
            .disabled(nutrition == nil)
            .accessibilityIdentifier("addFood.submit")
        }
        .vessStandaloneTitle("Manual entry", embedded: embedded, hidesTabBar: false)
        .vessErrorAlert(isPresented: $showError, retry: add)
        .vessKeyboardDoneButton()
    }

    private var macroFields: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: VESSSpacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: VESSSpacing.sm))
        return layout {
            // One section label above; each field names itself inside.
            VESSTextField("Protein", text: $protein, unit: "g", error: NutrientInput.grams(protein) == nil ? Text("0–1,000 g") : nil, titleInside: true) { focusedField = .protein }
                .id(Field.protein)
                .keyboardType(.decimalPad)
            VESSTextField("Carbs", text: $carbs, unit: "g", error: NutrientInput.grams(carbs) == nil ? Text("0–1,000 g") : nil, titleInside: true) { focusedField = .carbs }
                .id(Field.carbs)
                .keyboardType(.decimalPad)
            VESSTextField("Fat", text: $fat, unit: "g", error: NutrientInput.grams(fat) == nil ? Text("0–1,000 g") : nil, titleInside: true) { focusedField = .fat }
                .id(Field.fat)
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
                let entry = FoodLogEntry(userID: profile.id, food: food, portion: portion, mealType: meal, loggedAt: logTime)
                try store.add(entry)
                undo.show([entry], meal: meal)
            } else {
                let entry = FoodLogEntry(
                    id: UUID(), userID: profile.id, foodID: nil, foodName: trimmedName, mealType: meal,
                    quantity: count, servingUnit: .serving, nutrition: nutrition.scaled(by: count),
                    loggedAt: logTime, source: .userCreated
                )
                try store.add(entry)
                undo.show([entry], meal: meal)
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
