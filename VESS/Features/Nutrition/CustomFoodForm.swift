import SwiftUI

/// Create your own food. Saved on this device and searchable afterwards;
/// opens the food so a portion can be logged right away.
struct CustomFoodForm: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onSaved: (Food) -> Void

    @State private var name = ""
    @State private var brand = ""
    @State private var basisAmount = "100"
    @State private var basisUnit: QuantityUnit = .gram
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var showError = false

    private let units: [QuantityUnit] = [.gram, .milliliter, .serving]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                Text("Create a food")
                    .vessTextStyle(.detailTitle)

                VESSTextField("Name", text: $name, prompt: Text("For example, overnight oats"))
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("customFood.name")
                VESSTextField("Brand", text: $brand, prompt: Text("Optional"))

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text("Nutrition per")
                        .vessTextStyle(.label)
                    // Bottom-aligned so the unit picker centers on the field, not its label.
                    HStack(alignment: .bottom, spacing: VESSSpacing.sm) {
                        if basisUnit != .serving {
                            VESSTextField("Amount", text: $basisAmount)
                                .keyboardType(.decimalPad)
                        }
                        Picker("Unit", selection: $basisUnit) {
                            ForEach(units, id: \.self) { unit in
                                Text(unit == .serving ? "serving" : String(localized: unit.abbreviation)).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(minHeight: VESSHitTarget.control)
                    }
                }

                VESSTextField("Calories", text: $calories, unit: "kcal")
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("customFood.calories")
                macroFields

                Text("Leave a macro empty if the label doesn't list it.")
                    .vessTextStyle(.label)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(VESSColor.card)
        .vessBottomAction {
            Button("Save food", action: save)
                .buttonStyle(.vessPrimary)
                .disabled(food == nil)
                .accessibilityIdentifier("customFood.save")
        }
        .navigationBarTitleDisplayMode(.inline)
        .vessErrorAlert(isPresented: $showError, retry: save)
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

    private var food: Food? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = basisUnit == .serving ? 1 : VESSFormat.number(from: basisAmount)
        guard !trimmedName.isEmpty,
              let amount, amount > 0, amount <= 10_000,
              let kcal = VESSFormat.number(from: calories), (0...10_000).contains(kcal),
              let proteinGrams = NutrientInput.grams(protein),
              let carbGrams = NutrientInput.grams(carbs),
              let fatGrams = NutrientInput.grams(fat)
        else { return nil }

        let trimmedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return Food(
            id: UUID(),
            name: trimmedName,
            brand: trimmedBrand.isEmpty ? nil : trimmedBrand,
            barcode: nil,
            servingSize: amount,
            servingUnit: basisUnit,
            nutrition: NutrientInput.facts(calories: kcal, protein: proteinGrams, carbs: carbGrams, fat: fatGrams),
            ingredients: [],
            allergens: [],
            quality: nil,
            source: .userCreated,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func save() {
        guard let food else { return }
        do {
            try store.save(food)
            onSaved(food)
        } catch {
            showError = true
        }
    }
}
