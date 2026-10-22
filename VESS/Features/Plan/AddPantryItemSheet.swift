import SwiftUI

/// C03: add something you have at home. A scanned product fills the name
/// and amount; nothing is logged as eaten.
struct AddPantryItemSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantityText = "1"
    @State private var unit: QuantityUnit = .piece
    @State private var location: StorageLocation = .fridge
    @State private var expirationDate: Date?
    @State private var showScanner = false
    @State private var showError = false

    private let calendar = Calendar.current
    private let units: [QuantityUnit] = [.piece, .gram, .milliliter, .pack]

    /// - Parameter product: a product scanned before the sheet opened.
    init(product: Food? = nil) {
        _expirationDate = State(initialValue: ExpiryPreset.inAWeek.date(from: AppClock.now, calendar: .current))
        if let product {
            _name = State(initialValue: product.name)
            if let pack = Self.packSize(of: product) {
                _quantityText = State(initialValue: VESSFormat.quantity(pack.amount))
                _unit = State(initialValue: pack.unit)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    HStack {
                        Text("Add to pantry")
                            .vessTextStyle(.titleL)
                            .foregroundStyle(VESSColor.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                    }

                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        VESSTextField("Item", text: $name)
                            .textInputAutocapitalization(.sentences)
                            .accessibilityIdentifier("pantryAdd.name")
                        Button("Scan barcode") { showScanner = true }
                            .buttonStyle(.vessSecondary)
                            .accessibilityIdentifier("pantryAdd.scan")
                    }

                    HStack(alignment: .bottom, spacing: VESSSpacing.sm) {
                        VESSTextField("Quantity", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("pantryAdd.quantity")
                        Menu {
                            Picker("Unit", selection: $unit) {
                                ForEach(units, id: \.self) { unit in
                                    Text(unit.abbreviation).tag(unit)
                                }
                            }
                        } label: {
                            HStack(spacing: VESSSpacing.xxs) {
                                Text(unit.abbreviation)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.text)
                            .padding(.horizontal, VESSSpacing.md)
                            .frame(minHeight: VESSHitTarget.control)
                            .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous).strokeBorder(VESSColor.divider))
                        }
                        .accessibilityLabel(Text("Unit: \(Text(unit.abbreviation))"))
                    }

                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        VESSSectionHeader(title: "Stored in")
                        StorageLocationChips(location: $location)
                    }

                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        VESSSectionHeader(title: "Use by")
                        ExpiryChips(
                            date: $expirationDate,
                            presets: [.tomorrow, .inThreeDays, .inAWeek, .inAMonth, .noDate],
                            now: AppClock.now,
                            calendar: calendar
                        )
                    }
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(VESSColor.card)
            .vessBottomAction {
                Button("Add to pantry", action: add)
                    .buttonStyle(.vessPrimary)
                    .disabled(item == nil)
                    .accessibilityIdentifier("pantryAdd.submit")
            }
            .toolbar(.hidden, for: .navigationBar)
            .vessErrorAlert(isPresented: $showError, retry: add)
            .vessKeyboardDoneButton()
            .fullScreenCover(isPresented: $showScanner) {
                BarcodeScannerView(
                    day: AppClock.now,
                    meal: .constant(.dinner),
                    onLogged: { showScanner = false },
                    onTypeNumber: { showScanner = false },
                    onAddManually: { _ in showScanner = false },
                    onProduct: fill
                )
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    /// The item to save, or `nil` while the name or amount is missing.
    private var item: InventoryItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let quantity = VESSFormat.number(from: quantityText), quantity > 0, quantity <= 100_000
        else { return nil }
        return InventoryItem(
            id: UUID(), name: trimmed, quantity: quantity, unit: unit,
            purchaseDate: AppClock.now, expirationDate: expirationDate,
            category: .other, location: location, notes: nil,
            status: .available, reminderSnoozedUntil: nil
        )
    }

    /// A product's pack size in grams or millilitres, when it names one
    /// ("1 pot (150 g)").
    private static func packSize(of food: Food) -> (amount: Double, unit: QuantityUnit)? {
        let portion = food.defaultPortion
        guard !portion.option.isBaseUnit, [.gram, .milliliter].contains(food.servingUnit) else { return nil }
        return (portion.baseAmount, food.servingUnit)
    }

    private func fill(_ food: Food) {
        name = food.name
        if let pack = Self.packSize(of: food) {
            quantityText = VESSFormat.quantity(pack.amount)
            unit = pack.unit
        }
    }

    private func add() {
        guard let item else { return }
        do {
            try store.save(item)
            dismiss()
        } catch {
            showError = true
        }
    }
}
