import SwiftUI

extension GroceryAisle {
    var title: LocalizedStringResource {
        switch self {
        case .produce: "Produce"
        case .fish: "Fish"
        case .dairyEggs: "Dairy & eggs"
        case .bakery: "Bakery"
        case .pantryStaples: "Pantry staples"
        case .other: "Other"
        }
    }
}

/// Builds this week's list and writes the user's changes to it.
@MainActor
struct GroceryModel {
    let store: LocalStore
    let calendar: Calendar

    /// From today through the end of this week.
    func list(now: Date) -> GroceryList {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfWeek(for: now)) ?? today
        return GroceryList(
            planned: store.plannedMeals(from: today, to: end),
            pantry: store.inventory,
            states: store.groceryItems,
            from: now, to: end, calendar: calendar
        )
    }

    /// The stored state for a line, created on first change.
    func state(for line: GroceryList.Line, now: Date) -> GroceryItem {
        line.state ?? GroceryItem(
            id: UUID(), key: line.key, name: line.name, quantity: nil, unit: nil, aisle: nil,
            isChecked: false, isManual: line.isManual, isDismissed: false, createdAt: now
        )
    }

    func toggle(_ line: GroceryList.Line, now: Date) throws {
        var item = state(for: line, now: now)
        item.isChecked.toggle()
        try store.save(item)
    }

    /// "I already have it" or "Remove from list". A manual item is deleted;
    /// a plan line stays off the list for this week.
    func dismiss(_ line: GroceryList.Line, now: Date) throws {
        if line.isManual, let state = line.state {
            try store.deleteGroceryItem(id: state.id)
        } else {
            var item = state(for: line, now: now)
            item.isDismissed = true
            try store.save(item)
        }
    }

    /// Moves checked lines into the pantry, then clears them from the list.
    /// Returns how many were stored.
    @discardableResult
    func doneShopping(_ list: GroceryList, now: Date) throws -> Int {
        let items = list.pantryItems(now: now)
        for item in items { try store.save(item) }
        for line in list.checked {
            if let state = line.state { try store.deleteGroceryItem(id: state.id) }
        }
        return items.count
    }
}

/// B01–B03, B06: this week's grocery list, by aisle or by meal. Checking an
/// item doesn't store it; Done shopping moves checked items into the pantry.
/// Shown as Plan's Grocery segment.
struct GroceryContent: View {
    @Environment(LocalStore.self) private var store

    /// B06: "Plan meals" returns to the week.
    let onPlanMeals: () -> Void

    private enum Grouping: Hashable { case aisle, meal }

    @State private var grouping: Grouping = .aisle
    @State private var showAdd = false
    @State private var showError = false
    @State private var storedCount = 0

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let model = GroceryModel(store: store, calendar: calendar)
        let list = model.list(now: now)

        Group {
            if list.lines.isEmpty {
                empty
            } else {
                content(list, model: model, now: now)
            }
        }
        .sheet(isPresented: $showAdd) { AddGroceryItemSheet() }
        .vessErrorAlert(isPresented: $showError)
        .sensoryFeedback(.success, trigger: storedCount)
    }

    private func content(_ list: GroceryList, model: GroceryModel, now: Date) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.section) {
            VStack(alignment: .leading, spacing: VESSSpacing.md) {
                Text("\(list.toBuy.count) to buy")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)
                if list.plannedMealCount > 0 {
                    Text("For ^[\(list.plannedMealCount) planned meal](inflect: true) through Sunday")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                if list.leftOffCount > 0 {
                    note(list.leftOffCount == 1
                         ? Text("Updated from your plan. 1 thing you already have at home was left off.")
                         : Text("Updated from your plan. \(list.leftOffCount) things you already have at home were left off."))
                }
                Button("Add item") { showAdd = true }
                    .buttonStyle(.vessSecondary)
                    .accessibilityIdentifier("grocery.add")
                HStack(spacing: VESSSpacing.xs) {
                    VESSChip(title: "Aisle", isSelected: grouping == .aisle) { grouping = .aisle }
                    VESSChip(title: "Meal", isSelected: grouping == .meal) { grouping = .meal }
                }
            }

            switch grouping {
            case .aisle:
                ForEach(GroceryAisle.allCases, id: \.self) { aisle in
                    let lines = list.toBuy.filter { $0.aisle == aisle }
                    if !lines.isEmpty {
                        section(Text(aisle.title), lines: lines, detail: .meals, model: model, now: now)
                    }
                }
            case .meal:
                ForEach(mealGroups(list), id: \.id) { group in
                    section(Text(verbatim: group.title), lines: group.lines, detail: .aisle, model: model, now: now)
                }
                let manual = list.toBuy.filter(\.isManual)
                if !manual.isEmpty {
                    section(Text("Added by you"), lines: manual, detail: .aisle, model: model, now: now)
                }
            }

            if !list.checked.isEmpty {
                section(Text("Checked · \(list.checked.count) ready to store"), lines: list.checked, detail: .meals, model: model, now: now)
                note(Text("Checking items does not add them to Pantry. Tap Done shopping to move ^[these \(list.checked.count) checked item](inflect: true) into Pantry."))
                Button {
                    do {
                        try model.doneShopping(list, now: now)
                        storedCount += 1
                    } catch {
                        showError = true
                    }
                } label: {
                    Text("Done shopping · store ^[\(list.checked.count) item](inflect: true)")
                }
                .buttonStyle(.vessPrimary)
                .accessibilityIdentifier("grocery.done")
            }
        }
    }

    private enum Detail { case meals, aisle }

    private func section(_ title: Text, lines: [GroceryList.Line], detail: Detail, model: GroceryModel, now: Date) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            title
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            VESSRowGroup {
                ForEach(lines) { line in
                    row(line, detail: detail, model: model, now: now)
                }
            }
            .vessHairlineBottom()
        }
    }

    private func row(_ line: GroceryList.Line, detail: Detail, model: GroceryModel, now: Date) -> some View {
        HStack(spacing: VESSSpacing.xxs) {
            Button {
                do { try model.toggle(line, now: now) } catch { showError = true }
            } label: {
                Image(systemName: line.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(line.isChecked ? VESSColor.text : VESSColor.tertiaryText)
                    .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The 44 pt target extends into the margin; the circle sits on it.
            .padding(.leading, -VESSSpacing.sm)
            .accessibilityLabel(Text(line.name))
            .accessibilityValue(line.isChecked ? Text("Checked") : Text("Not checked"))
            .accessibilityHint("Checking doesn't add it to your pantry.")
            .accessibilityIdentifier("grocery.check.\(line.name)")

            NavigationLink {
                GroceryItemView(key: line.key)
            } label: {
                VESSRow(
                    // Checked items read quieter, without hiding them.
                    title: Text(line.name).foregroundStyle(line.isChecked ? VESSColor.secondaryText : VESSColor.text),
                    subtitle: subtitle(line, detail: detail),
                    subtitleLineLimit: 2
                ) {
                    if let amount = PlannedMeal.Item(name: line.name, quantity: line.quantity, unit: line.unit).amountText {
                        Text(amount)
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("grocery.item.\(line.name)")
        }
    }

    private func subtitle(_ line: GroceryList.Line, detail: Detail) -> Text {
        switch detail {
        case .aisle: Text(line.aisle.title)
        case .meals: line.isManual ? Text("Added by you") : Text(verbatim: line.meals.map(\.name).joined(separator: " · "))
        }
    }

    /// B02: each planned meal with the lines it needs, by day.
    private func mealGroups(_ list: GroceryList) -> [(id: UUID, title: String, lines: [GroceryList.Line])] {
        var order: [PlannedMeal] = []
        for line in list.toBuy {
            for meal in line.meals where !order.contains(where: { $0.id == meal.id }) { order.append(meal) }
        }
        return order
            .sorted { $0.day < $1.day }
            .map { meal in (meal.id, meal.name, list.toBuy.filter { line in line.meals.contains { $0.id == meal.id } }) }
    }

    private func note(_ text: Text) -> some View {
        text
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(VESSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider))
    }

    /// B06.
    private var empty: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            Text("Nothing to buy")
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("Plan a few meals and VESS builds the list, leaving out what's already at home.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: VESSSpacing.sm) {
                Button("Plan meals", action: onPlanMeals)
                    .buttonStyle(.vessPrimary)
                Button("Add an item yourself") { showAdd = true }
                    .buttonStyle(.vessSecondary)
                    .accessibilityIdentifier("grocery.add")
            }
            .padding(.top, VESSSpacing.xs)
        }
        .padding(.top, VESSSpacing.huge)
    }
}

/// B04: one item. Its amount and aisle, the meals that need it, and
/// "I already have it" or "Remove from list".
struct GroceryItemView: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let key: String

    @State private var showError = false
    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let model = GroceryModel(store: store, calendar: calendar)

        Group {
            if let line = model.list(now: now).lines.first(where: { $0.key == key }) {
                content(line, model: model, now: now)
            } else {
                Color.clear
            }
        }
        .vessScreenBackground()
        .vessDetailTitle("Grocery")
        .vessErrorAlert(isPresented: $showError)
    }

    private func content(_ line: GroceryList.Line, model: GroceryModel, now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    Text(line.name)
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .accessibilityAddTraits(.isHeader)
                    (line.isManual ? Text("Added by you") : Text("For ^[\(line.meals.count) planned meal](inflect: true)"))
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Quantity")
                    quantity(line, model: model, now: now)
                }

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Aisle")
                    VESSChipFlow {
                        ForEach(GroceryAisle.allCases, id: \.self) { aisle in
                            VESSChip(title: aisle.title, isSelected: line.aisle == aisle) {
                                update(line, model: model, now: now) { $0.aisle = aisle }
                            }
                        }
                    }
                }

                if !line.meals.isEmpty {
                    VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                        VESSSectionHeader(title: "Needed for")
                        VESSRowGroup {
                            ForEach(line.meals) { meal in
                                VESSRow(
                                    title: Text(meal.name),
                                    subtitle: Text("\(Text(meal.day, format: .dateTime.weekday(.wide))) · \(Text(meal.mealType.title))")
                                ) { EmptyView() }
                            }
                        }
                        .vessHairlineBottom()
                    }
                }

                VStack(spacing: VESSSpacing.sm) {
                    if !line.isManual {
                        Button("I already have it") { dismissLine(line, model: model, now: now) }
                            .buttonStyle(.vessSecondary)
                            .accessibilityIdentifier("groceryItem.have")
                    }
                    Button("Remove from list") { dismissLine(line, model: model, now: now) }
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("groceryItem.remove")
                }
                .padding(.top, VESSSpacing.sm)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
    }

    /// − 350 g +, by 50 g or ml, or one at a time.
    private func quantity(_ line: GroceryList.Line, model: GroceryModel, now: Date) -> some View {
        let unit = line.unit ?? .piece
        let value = line.quantity ?? 1
        let step: Double = [.gram, .milliliter].contains(unit) ? 50 : 1
        return HStack {
            VESSIconButton(systemImage: "minus", label: "Less") {
                update(line, model: model, now: now) {
                    $0.quantity = max(step, ((value / step).rounded() - 1) * step)
                    $0.unit = unit
                }
            }
            .disabled(value <= step)
            Spacer()
            Text(PlannedMeal.Item(name: line.name, quantity: value, unit: unit).amountText ?? "")
                .vessTextStyle(.displayM)
                .foregroundStyle(VESSColor.text)
                .contentTransition(.numericText())
            Spacer()
            VESSIconButton(systemImage: "plus", label: "More") {
                update(line, model: model, now: now) {
                    $0.quantity = ((value / step).rounded() + 1) * step
                    $0.unit = unit
                }
            }
        }
    }

    private func update(_ line: GroceryList.Line, model: GroceryModel, now: Date, _ change: (inout GroceryItem) -> Void) {
        var item = model.state(for: line, now: now)
        change(&item)
        do { try store.save(item) } catch { showError = true }
    }

    private func dismissLine(_ line: GroceryList.Line, model: GroceryModel, now: Date) {
        do {
            try model.dismiss(line, now: now)
            dismiss()
        } catch {
            showError = true
        }
    }
}

/// B05: add something to the list yourself.
struct AddGroceryItemSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantityText = "1"
    @State private var unit: QuantityUnit = .piece
    @State private var aisle: GroceryAisle = .other
    @State private var aisleChosen = false
    @State private var showError = false

    private let units: [QuantityUnit] = [.piece, .gram, .milliliter, .pack]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    HStack {
                        Text("Add to grocery list")
                            .vessTextStyle(.titleL)
                            .foregroundStyle(VESSColor.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                    }

                    VESSTextField("Item", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("groceryAdd.name")
                        .onChange(of: name) { _, new in
                            // The aisle follows the name until one is chosen.
                            if !aisleChosen { aisle = GroceryAisle.guess(for: new) }
                        }

                    HStack(alignment: .bottom, spacing: VESSSpacing.sm) {
                        VESSTextField("Quantity", text: $quantityText)
                            .keyboardType(.decimalPad)
                        Menu {
                            Picker("Unit", selection: $unit) {
                                ForEach(units, id: \.self) { Text($0.abbreviation).tag($0) }
                            }
                        } label: {
                            HStack(spacing: VESSSpacing.xxs) {
                                Text(unit.abbreviation)
                                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
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
                        VESSSectionHeader(title: "Aisle")
                        VESSChipFlow {
                            ForEach(GroceryAisle.allCases, id: \.self) { option in
                                VESSChip(title: option.title, isSelected: aisle == option) {
                                    aisle = option
                                    aisleChosen = true
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(VESSColor.card)
            .vessBottomAction {
                Button("Add to list", action: add)
                    .buttonStyle(.vessPrimary)
                    .disabled(item == nil)
                    .accessibilityIdentifier("groceryAdd.submit")
            }
            .toolbar(.hidden, for: .navigationBar)
            .vessErrorAlert(isPresented: $showError, retry: add)
            .vessKeyboardDoneButton()
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    private var item: GroceryItem? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let quantity = VESSFormat.number(from: quantityText), quantity > 0, quantity <= 100_000 else { return nil }
        return GroceryItem(
            id: UUID(), key: GroceryList.key(for: trimmed), name: trimmed, quantity: quantity, unit: unit,
            aisle: aisle, isChecked: false, isManual: true, isDismissed: false, createdAt: AppClock.now
        )
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
