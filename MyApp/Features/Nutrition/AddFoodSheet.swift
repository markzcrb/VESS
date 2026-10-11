import SwiftUI

/// A request to open the food sheet for a meal on a day.
struct AddFoodRequest: Identifiable {
    let id = UUID()
    var meal: MealType
    var day: Date
}

/// Quick add: log a food by entering what you know, without a product.
/// Shown inside `FoodSearchSheet`. A macro left empty is saved as
/// "not reported", never as zero.
struct QuickAddForm: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let day: Date
    @Binding var meal: MealType
    let onLogged: () -> Void

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                MealPickerHeader(title: "Add to", subtitle: "Quick add", meal: $meal)

                VESSTextField("Food", text: $name, prompt: Text("For example, chicken salad"))
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("addFood.name")

                VESSTextField("Calories", text: $calories, unit: "kcal")
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("addFood.calories")

                macroFields

                Text("Leave a macro empty if you don't know it. It shows as not reported, not as zero.")
                    .vessTextStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(VESSColor.card)
        .vessBottomAction {
            Button(action: add) {
                Text("Add to \(Text(meal.title))")
            }
            .buttonStyle(.vessPrimary)
            .disabled(entry == nil)
            .accessibilityIdentifier("addFood.submit")
        }
        .navigationBarTitleDisplayMode(.inline)
        .vessErrorAlert(isPresented: $showError, retry: add)
        .vessKeyboardDoneButton()
    }

    private var macroFields: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: VESSSpacing.md))
            : AnyLayout(HStackLayout(spacing: VESSSpacing.sm))
        return layout {
            VESSTextField("Protein", text: $protein, unit: "g").keyboardType(.decimalPad)
            VESSTextField("Carbs", text: $carbs, unit: "g").keyboardType(.decimalPad)
            VESSTextField("Fat", text: $fat, unit: "g").keyboardType(.decimalPad)
        }
    }

    /// The entry to save, or `nil` while the form is incomplete or invalid.
    private var entry: FoodLogEntry? {
        guard let profile = store.profile else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let kcal = VESSFormat.number(from: calories), (0...5000).contains(kcal),
              let proteinGrams = NutrientInput.grams(protein),
              let carbGrams = NutrientInput.grams(carbs),
              let fatGrams = NutrientInput.grams(fat)
        else { return nil }

        return FoodLogEntry(
            id: UUID(),
            userID: profile.id,
            foodID: nil,
            foodName: trimmedName,
            mealType: meal,
            quantity: 1,
            servingUnit: .serving,
            nutrition: NutrientInput.facts(calories: kcal, protein: proteinGrams, carbs: carbGrams, fat: fatGrams),
            loggedAt: logTime,
            source: .userCreated
        )
    }

    /// Now for today; the meal's typical time for a past day.
    private var logTime: Date {
        if calendar.isDateInToday(day) { return .now }
        let time = meal.typicalTime
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }

    private func add() {
        guard let entry else { return }
        do {
            try store.add(entry)
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
