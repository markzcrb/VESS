import SwiftUI

/// C02: one pantry item. Change the amount, where it's kept and when to use
/// it by; or mark it used up or thrown away (both kept for food-waste
/// insights), or delete it.
struct PantryItemView: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let itemID: UUID

    @State private var draft: InventoryItem?
    @State private var showDeleteConfirmation = false
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if let item = Binding($draft) {
                content(item)
            } else {
                Color.clear
            }
        }
        .vessScreenBackground()
        .vessDetailTitle("Pantry")
        .onAppear { if draft == nil { draft = store.inventoryItem(id: itemID) } }
        .vessErrorAlert(isPresented: $showError)
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("It's removed from your pantry and not counted as used or thrown away.")
        }
    }

    private func content(_ item: Binding<InventoryItem>) -> some View {
        let value = item.wrappedValue
        return ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    Text(value.name)
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    summary(value)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Quantity")
                    quantityStepper(item)
                }

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Stored in")
                    StorageLocationChips(location: item.location)
                }

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Expires", detail: expiresDetail(value))
                    ExpiryChips(date: item.expirationDate, now: AppClock.now, calendar: calendar)
                    // A date that matches no chip gets its own picker.
                    if let date = value.expirationDate,
                       ExpiryPreset.matching(date, now: AppClock.now, calendar: calendar) == nil {
                        DatePicker(
                            "Use by",
                            selection: Binding(
                                get: { date },
                                set: { item.wrappedValue.expirationDate = calendar.startOfDay(for: $0) }
                            ),
                            displayedComponents: .date
                        )
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                    }
                }

                VStack(spacing: VESSSpacing.sm) {
                    Button("Save changes", action: saveChanges)
                        .buttonStyle(.vessPrimary)
                        .disabled(value == store.inventoryItem(id: itemID))
                        .accessibilityIdentifier("pantryItem.save")
                    Button("Used it all") { finish(as: .consumed) }
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("pantryItem.used")
                    Button("Threw it away") { finish(as: .discarded) }
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("pantryItem.discarded")
                    Button("Delete") { showDeleteConfirmation = true }
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("pantryItem.delete")
                }
                .padding(.top, VESSSpacing.md)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
    }

    /// "Fridge · use by 7 Oct" or "Fridge · no date".
    private func summary(_ item: InventoryItem) -> Text {
        guard let date = item.expirationDate else {
            return Text("\(Text(item.location.title)) · no date")
        }
        return Text("\(Text(item.location.title)) · use by \(date, format: .dateTime.day().month(.abbreviated))")
    }

    /// "TOMORROW, 7 OCT" beside the header.
    private func expiresDetail(_ item: InventoryItem) -> Text? {
        guard let date = item.expirationDate else { return nil }
        let day = Text(date, format: .dateTime.day().month(.abbreviated))
        guard let relative = item.expirationStatus(now: AppClock.now, calendar: calendar).relativeText else { return day }
        return Text("\(relative), \(day)")
    }

    /// − 150 g +, by 50 g or ml, or one at a time for counts.
    private func quantityStepper(_ item: Binding<InventoryItem>) -> some View {
        let value = item.wrappedValue
        let step: Double = [.gram, .milliliter].contains(value.unit) ? 50 : 1
        return HStack {
            VESSIconButton(systemImage: "minus", label: "Less") {
                item.wrappedValue.quantity = max(step, ((value.quantity / step).rounded() - 1) * step)
            }
            .disabled(value.quantity <= step)
            Spacer()
            Text(value.quantityText)
                .vessTextStyle(.displayM)
                .foregroundStyle(VESSColor.text)
                .contentTransition(.numericText())
            Spacer()
            VESSIconButton(systemImage: "plus", label: "More") {
                item.wrappedValue.quantity = ((value.quantity / step).rounded() + 1) * step
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(value.quantityText))
    }

    // MARK: Actions

    private func saveChanges() {
        guard let draft else { return }
        do {
            try store.save(draft)
            dismiss()
        } catch {
            showError = true
        }
    }

    private func finish(as status: InventoryStatus) {
        guard var item = draft else { return }
        item.status = status
        do {
            try store.save(item)
            dismiss()
        } catch {
            showError = true
        }
    }

    private func delete() {
        do {
            try store.deleteInventoryItem(id: itemID)
            dismiss()
        } catch {
            showError = true
        }
    }
}
