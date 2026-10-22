import SwiftUI

/// Edit a logged entry: its meal and amount. Nutrition is rescaled from the
/// snapshot saved when it was logged, so it never changes if the food does.
struct EditEntrySheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let entry: FoodLogEntry
    @State private var meal: MealType
    @State private var countText: String
    @State private var showError = false

    init(entry: FoodLogEntry) {
        self.entry = entry
        _meal = State(initialValue: entry.mealType)
        _countText = State(initialValue: VESSFormat.quantity(entry.portionCount))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                        Text(entry.foodName)
                            .vessTextStyle(.detailTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Logged at \(entry.loggedAt, format: .dateTime.hour().minute())")
                            .vessTextStyle(.secondary)
                    }

                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.dayOrder) { meal in
                            Text(meal.title).tag(meal)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editEntry.meal")

                    VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                        VESSTextField(amountTitle, text: $countText, unit: amountUnit)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("editEntry.amount")
                        if let portionLabel = entry.portionLabel, let amount = entry.portionAmount, let count {
                            Text("\(VESSFormat.quantity(count)) × \(portionLabel) (\(VESSFormat.quantity(amount * count)) \(Text(entry.servingUnit.abbreviation)))")
                                .vessTextStyle(.label)
                        }
                    }

                    NutrientList(nutrition: updated?.nutrition ?? entry.nutrition)
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.bottom, VESSSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(VESSColor.card)
            .vessBottomAction {
                VStack(spacing: VESSSpacing.xs) {
                    Button("Save", action: save)
                        .buttonStyle(.vessPrimary)
                        .disabled(updated == nil)
                        .accessibilityIdentifier("editEntry.save")
                    Button("Delete entry", role: .destructive, action: delete)
                        .font(.body)
                        .foregroundStyle(VESSColor.criticalText)
                        .frame(minHeight: VESSHitTarget.minimum)
                        .accessibilityIdentifier("editEntry.delete")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .vessErrorAlert(isPresented: $showError)
            .vessKeyboardDoneButton()
        }
        .presentationCornerRadius(VESSRadius.sheet)
        .presentationDragIndicator(.visible)
    }

    /// Portions are edited as a count ("1.5 slices"); everything else in its unit.
    private var amountTitle: LocalizedStringKey {
        entry.portionLabel == nil ? "Amount" : "Portions"
    }

    private var amountUnit: LocalizedStringKey? {
        guard entry.portionLabel == nil else { return nil }
        return LocalizedStringKey(String(localized: entry.servingUnit.abbreviation))
    }

    private var count: Double? {
        guard let value = VESSFormat.number(from: countText), value > 0, value <= 10_000 else { return nil }
        return value
    }

    private var updated: FoodLogEntry? {
        count.map { entry.updated(portionCount: $0, mealType: meal) }
    }

    private func save() {
        guard let updated else { return }
        do {
            try store.update(updated)
            dismiss()
        } catch {
            showError = true
        }
    }

    private func delete() {
        do {
            try store.deleteFoodEntry(id: entry.id)
            dismiss()
        } catch {
            showError = true
        }
    }
}
