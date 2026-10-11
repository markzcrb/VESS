import SwiftUI

/// Quick add: log a food by entering what you know. Search, barcode and
/// photo logging build on this sheet in later phases.
struct AddFoodSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let day: Date
    @State private var meal: MealType
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var showError = false

    private let calendar = Calendar.current

    init(request: AddFoodRequest) {
        day = request.day
        _meal = State(initialValue: request.meal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    header

                    VESSTextField("Food", text: $name, prompt: Text("For example, chicken salad"))
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("addFood.name")

                    VESSTextField("Calories", text: $calories, unit: "kcal")
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("addFood.calories")

                    macroFields

                    Text("Leave macros empty if you don't know them.")
                        .vessTextStyle(.label)
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.bottom, VESSSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(VESSColor.card)
            .safeAreaInset(edge: .bottom) {
                Button(action: add) {
                    Text("Add to \(Text(meal.title))")
                }
                .buttonStyle(.vessPrimary)
                .disabled(entry == nil)
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.vertical, VESSSpacing.sm)
                .background(VESSColor.card)
                .accessibilityIdentifier("addFood.submit")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .vessErrorAlert(isPresented: $showError, retry: add)
            .vessKeyboardDoneButton()
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                Text("Add to")
                    .vessTextStyle(.detailTitle)
                Menu {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.dayOrder) { meal in
                            Text(meal.title).tag(meal)
                        }
                    }
                } label: {
                    HStack(spacing: VESSSpacing.xxs) {
                        Text(meal.title)
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(VESSColor.accent)
                }
                .accessibilityLabel(Text("Meal: \(Text(meal.title))"))
            }
            Text("Quick add")
                .vessTextStyle(.secondary)
        }
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
              let proteinGrams = optionalGrams(protein),
              let carbGrams = optionalGrams(carbs),
              let fatGrams = optionalGrams(fat)
        else { return nil }

        return FoodLogEntry(
            id: UUID(),
            userID: profile.id,
            foodID: nil,
            foodName: trimmedName,
            mealType: meal,
            quantity: 1,
            servingUnit: .serving,
            nutrition: NutritionFacts(
                calories: kcal,
                proteinGrams: proteinGrams,
                carbohydrateGrams: carbGrams,
                fatGrams: fatGrams
            ),
            loggedAt: logTime
        )
    }

    /// Empty means 0; otherwise the value must be a plausible gram amount.
    private func optionalGrams(_ text: String) -> Double? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        guard let value = VESSFormat.number(from: text), (0...1000).contains(value) else { return nil }
        return value
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
            dismiss()
        } catch {
            showError = true
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddFoodSheet(request: AddFoodRequest(meal: .dinner, day: .now))
                .environment(LocalStore.preview(.profileOnly))
        }
}
