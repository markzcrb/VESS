import SwiftUI
import VisionKit

/// Something to add as an ingredient (R04): a USDA generic food, an Open
/// Food Facts product or a pantry item (with the USDA food it matches).
struct IngredientChoice: Identifiable {
    enum Kind {
        case generic(GenericFood)
        case product(Food)
        /// A pantry item and its USDA food, if one matched or was chosen.
        case pantry(InventoryItem, GenericFood?)
        /// An ingredient already in the recipe, being changed.
        case existing(Recipe.Ingredient)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .generic(let food): "usda.\(food.id)"
        case .product(let food): "off.\(food.barcode ?? food.id.uuidString)"
        case .pantry(let item, _): "pantry.\(item.id)"
        case .existing(let ingredient): "existing.\(ingredient.name)"
        }
    }

    var name: String {
        switch kind {
        case .generic(let food): food.name
        case .product(let food): food.name
        case .pantry(let item, _): item.name
        case .existing(let ingredient): ingredient.name
        }
    }

    /// "Chickpeas" for "Chickpeas (garbanzo beans, bengal gram), mature seeds,
    /// raw": the part before the first comma, without brackets.
    var shortName: String {
        let plain = name.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        return plain.prefix { $0 != "," }.trimmingCharacters(in: .whitespaces)
    }

    /// Per 100 g (or ml); `nil` without nutrition data.
    var per100: NutritionFacts? {
        switch kind {
        case .generic(let food): food.per100g
        case .product(let food): food.servingSize > 0 ? food.nutrition(forQuantity: 100) : nil
        case .pantry(_, let food): food?.per100g
        case .existing(let ingredient): ingredient.per100
        }
    }

    /// Grams or millilitres first, then household portions.
    var units: [ServingOption] {
        switch kind {
        case .generic(let food): food.units
        case .product(let food):
            [.baseUnit(food.servingUnit == .milliliter ? .milliliter : .gram)] + (food.servingOptions ?? [])
        case .pantry(_, let food): food?.units ?? [.baseUnit(.gram)]
        case .existing(let ingredient):
            ingredient.unit == .milliliter ? [.baseUnit(.milliliter)] : [.baseUnit(.gram)]
        }
    }

    var isMilliliters: Bool { units.first?.label == QuantityUnit.milliliter.rawValue }

    /// The ingredient for `count` of `unit`.
    func ingredient(count: Double, unit: ServingOption) -> Recipe.Ingredient {
        let grams = unit.isBaseUnit ? count : count * unit.amount
        let (recipeUnit, quantity) = Self.recipeUnit(for: unit, count: count, grams: grams, milliliters: isMilliliters)
        var allergens = RecipeDerivation.allergens(forName: name)
        let source: Recipe.Ingredient.Source?
        var key = name.lowercased()
        switch kind {
        case .generic(let food):
            source = .usda(ndb: food.id)
            allergens.formUnion(RecipeDerivation.allergens(forName: food.name))
        case .product(let food):
            source = food.barcode.map { .openFoodFacts(barcode: $0) } ?? .user
            allergens.formUnion(food.allergens)
        case .pantry(let item, let food):
            source = food.map { .usda(ndb: $0.id) }
            key = item.name.lowercased()
            if let food { allergens.formUnion(RecipeDerivation.allergens(forName: food.name)) }
        case .existing(let ingredient):
            source = ingredient.source
            key = ingredient.key ?? key
            allergens.formUnion(ingredient.allergens)
        }
        // USDA names lose their brackets: "Chickpeas, mature seeds, raw".
        let shown = if case .generic = kind {
            name.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        } else {
            name
        }
        return Recipe.Ingredient(
            name: shown, key: key, quantity: quantity, unit: recipeUnit, grams: grams,
            allergens: allergens, source: source, per100: per100
        )
    }

    /// A household portion as a recipe unit: tbsp, tsp, clove, slice or a
    /// piece; cups, cans and ounces become grams.
    static func recipeUnit(for unit: ServingOption, count: Double, grams: Double, milliliters: Bool) -> (Recipe.Unit, Double) {
        if unit.isBaseUnit { return (milliliters ? .milliliter : .gram, count) }
        let label = FoodSearch.normalized(unit.label)
        if label.contains("tbsp") || label.contains("tablespoon") { return (.tablespoon, count) }
        if label.contains("tsp") || label.contains("teaspoon") { return (.teaspoon, count) }
        if label.contains("clove") { return (.clove, count) }
        if label.contains("slice") { return (.slice, count) }
        if label == "1 cup" || label == "cup" { return (.cup, count) }
        if ["cup", "can", "oz", "fl", "package", "container", "jar", "pint"].contains(where: { label.contains($0) }) {
            return (milliliters ? .milliliter : .gram, grams)
        }
        return (.piece, count)
    }

    /// "tin (240 g)", "cup", "tbsp": a portion without its leading "1".
    static func unitTitle(_ unit: ServingOption, milliliters: Bool) -> String {
        if unit.isBaseUnit { return milliliters ? "ml" : "g" }
        var label = unit.label
        if label.hasPrefix("1 ") { label.removeFirst(2) }
        let plain = ["cup", "tbsp", "tsp"].contains(FoodSearch.normalized(label))
        return plain ? label : "\(label) (\(VESSFormat.quantity(unit.amount))\u{00A0}g)"
    }
}

/// R04: search generic foods (USDA), products (Open Food Facts) and the
/// pantry; pick an amount and a unit; see its nutrition; add it.
struct AddIngredientSheet: View {
    enum Source: CaseIterable {
        case all, generic, brands, pantry

        var title: LocalizedStringResource {
            switch self {
            case .all: "All"
            case .generic: "Generic · USDA"
            case .brands: "Brands · OFF"
            case .pantry: "My pantry"
            }
        }
    }

    var existing: Recipe.Ingredient?
    let onAdd: (Recipe.Ingredient) -> Void

    @Environment(LocalStore.self) private var store
    @Environment(GenericFoodDatabase.self) private var foods
    @Environment(FoodLookupService.self) private var lookup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var query = ""
    @State private var source: Source = .all
    @State private var products: [Food] = []
    @State private var productsFailed = false
    @State private var selected: IngredientChoice?
    @State private var count: Double = 100
    @State private var unitIndex = 0
    /// "Choose food" on a pantry item: the USDA food picked next is remembered for it.
    @State private var matchingItem: InventoryItem?
    @State private var showsScanner = false
    @State private var moreGeneric = false
    @State private var moreBrands = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSearchField(prompt: "Search foods", text: $query) {
                        if DataScannerViewController.isSupported {
                            Button { showsScanner = true } label: {
                                Image(systemName: "barcode.viewfinder")
                                    .font(.body)
                                    .foregroundStyle(VESSColor.secondaryText)
                                    .frame(width: VESSHitTarget.minimum, height: VESSHitTarget.minimum)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Scan a barcode")
                        }
                    }
                    .accessibilityIdentifier("ingredient.search")

                    VESSBleedingRow {
                        HStack(spacing: VESSSpacing.xs) {
                            ForEach(Source.allCases, id: \.self) { option in
                                VESSChip(title: option.title, isSelected: source == option) { source = option }
                            }
                        }
                    }

                    amountCard
                        .id("amount")

                    if let matchingItem {
                        Text("Choose the food that matches \(matchingItem.name). UMEVA remembers it for next time.")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    results
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.bottom, VESSSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: selected?.id) { _, id in
                if id != nil { withAnimation(VESSMotion.selection) { proxy.scrollTo("amount", anchor: .top) } }
            }
            }
            .safeAreaInset(edge: .bottom) { addButton }
            .background(VESSColor.card)
            .vessDetailTitle(existing == nil ? "Add ingredient" : "Change ingredient")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
            }
            .task(id: query) { await searchProducts() }
            .onChange(of: query) { moreGeneric = false; moreBrands = false }
            .task { await foods.load() }
            .onAppear(perform: startWithExisting)
            .sheet(isPresented: $showsScanner) { scanner }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
        .presentationBackground(VESSColor.card)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let all = source == .all
        // With All: six of each, more on request.
        let genericFound = source == .all || source == .generic ? foods.search(trimmed, limit: 30) : []
        let generic = all && !moreGeneric ? Array(genericFound.prefix(Self.allLimit)) : genericFound
        let brandsFound = source == .all || source == .brands ? Array(products.prefix(20)) : []
        let brands = all && !moreBrands ? Array(brandsFound.prefix(Self.allLimit)) : brandsFound
        let pantry = source == .all || source == .pantry ? pantryItems(trimmed) : []
        // "Skyr", "quark" or a brand: USDA hasn't got it, so products first.
        let productsFirst = all && !trimmed.isEmpty && !foods.hasOwnNameMatch(trimmed)

        if trimmed.isEmpty && source != .pantry {
            Text("Search for a food, such as chickpeas or oats. Generic foods come from USDA FoodData Central; products from Open Food Facts.")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, VESSSpacing.sm)
        } else if generic.isEmpty && brands.isEmpty && pantry.isEmpty {
            Text(productsFailed && source != .generic && source != .pantry
                 ? "No matches here, and Open Food Facts can't be reached right now."
                 : "No foods match “\(trimmed)”.")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, VESSSpacing.sm)
        } else {
            VESSRowGroup {
                if productsFirst {
                    brandRows(brands, showsMore: all && !moreBrands && brandsFound.count > Self.allLimit)
                    genericRows(generic, showsMore: all && !moreGeneric && genericFound.count > Self.allLimit)
                } else {
                    genericRows(generic, showsMore: all && !moreGeneric && genericFound.count > Self.allLimit)
                    brandRows(brands, showsMore: all && !moreBrands && brandsFound.count > Self.allLimit)
                }
                ForEach(pantry, id: \.id) { item in
                    let match = foods.food(for: item)
                    resultRow(IngredientChoice(kind: .pantry(item, match)), subtitle: pantrySubtitle(item, match: match), pantryItem: match == nil ? item : nil)
                }
            }
            .vessHairlineBottom()
            if productsFailed && source == .all && trimmed.count >= 3 {
                Text("Open Food Facts can't be reached right now, so only generic foods and your pantry are shown.")
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Results per source under All.
    static let allLimit = 6

    @ViewBuilder
    private func genericRows(_ foods: [GenericFood], showsMore: Bool) -> some View {
        ForEach(foods) { food in
            resultRow(IngredientChoice(kind: .generic(food)), subtitle: Text("Generic · USDA · per 100\u{00A0}g"))
        }
        if showsMore { showMoreRow("Show more generic foods") { moreGeneric = true } }
    }

    @ViewBuilder
    private func brandRows(_ products: [Food], showsMore: Bool) -> some View {
        ForEach(products) { food in
            let brand = food.brand.map { "\($0) · " } ?? ""
            resultRow(IngredientChoice(kind: .product(food)), subtitle: Text("\(brand)Open Food Facts · per 100 \(food.servingUnit == .milliliter ? "ml" : "g")"))
        }
        if showsMore { showMoreRow("Show more products") { moreBrands = true } }
    }

    private func showMoreRow(_ title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .vessTextStyle(.labelCapsLink)
                .foregroundStyle(VESSColor.accent)
                .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pantryItems(_ query: String) -> [InventoryItem] {
        let available = store.inventory.filter { $0.status == .available }
        guard !query.isEmpty else { return available }
        let terms = IngredientMatcher.words(query)
        return available.filter { item in
            let words = IngredientMatcher.words(item.name)
            return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
        }
    }

    private func pantrySubtitle(_ item: InventoryItem, match: GenericFood?) -> Text {
        let amount = item.quantity.map { "\(VESSFormat.quantity($0)) \(String(localized: item.unit.abbreviation))" } ?? String(localized: "some")
        guard match != nil else { return Text("In your pantry · \(amount) · No nutrition data") }
        return Text("In your pantry · \(amount) · per 100\u{00A0}g")
    }

    private func resultRow(_ choice: IngredientChoice, subtitle: Text, pantryItem: InventoryItem? = nil) -> some View {
        Button { choose(choice) } label: {
            // The kcal goes under the name at accessibility sizes.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: VESSSpacing.md))
            layout {
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text(choice.name)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    subtitle
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let pantryItem {
                        Button {
                            matchingItem = pantryItem
                            query = pantryItem.name
                            source = .generic
                        } label: {
                            Text("Choose food")
                                .vessTextStyle(.labelCapsLink)
                                .foregroundStyle(VESSColor.accent)
                                .frame(minHeight: VESSHitTarget.minimum, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: VESSSpacing.sm) }
                if let per100 = choice.per100 {
                    Text("\(VESSFormat.calories(per100.calories))\u{00A0}kcal")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, VESSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: VESSSize.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected?.id == choice.id ? .isSelected : [])
    }

    // MARK: Amount

    @ViewBuilder
    private var amountCard: some View {
        if let selected {
            let units = selected.units
            let unit = units[min(unitIndex, units.count - 1)]
            let ingredient = selected.ingredient(count: count, unit: unit)
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    Text(selected.name)
                        .vessTextStyle(.labelCapsS)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .lineLimit(2)
                    HStack {
                        VESSIconButton(systemImage: "minus", label: "Less") { count = max(step(unit), count - step(unit)) }
                            .disabled(count <= step(unit))
                        Spacer()
                        Text("\(VESSFormat.quantity(count)) \(Text(IngredientChoice.unitTitle(unit, milliliters: selected.isMilliliters)).font(.body).foregroundStyle(VESSColor.secondaryText))")
                            .vessTextStyle(.displayM)
                            .foregroundStyle(VESSColor.text)
                            .monospacedDigit()
                        Spacer()
                        VESSIconButton(systemImage: "plus", label: "More") { count += step(unit) }
                    }
                    if units.count > 1 {
                        VESSBleedingRow {
                            HStack(spacing: VESSSpacing.xs) {
                                ForEach(units.indices, id: \.self) { index in
                                    VESSChip(
                                        title: LocalizedStringResource(stringLiteral: IngredientChoice.unitTitle(units[index], milliliters: selected.isMilliliters)),
                                        isSelected: index == unitIndex
                                    ) { selectUnit(index, units: units) }
                                }
                            }
                        }
                    }
                    if let per100 = selected.per100 {
                        let facts = per100.scaled(by: (ingredient.grams ?? 0) / 100)
                        Text("\(VESSFormat.calories(facts.calories))\u{00A0}kcal · \(VESSFormat.grams(facts.proteinGrams))\u{00A0}g protein · \(VESSFormat.grams(facts.carbohydrateGrams))\u{00A0}g carbs · \(VESSFormat.grams(facts.fatGrams))\u{00A0}g fat")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No nutrition data. It's added, and the recipe's total says Partial.")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(VESSSpacing.lg)
                .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
        }
    }

    @ViewBuilder
    private var addButton: some View {
        if let selected {
            let units = selected.units
            let unit = units[min(unitIndex, units.count - 1)]
            let amount = "\(VESSFormat.quantity(count)) \(IngredientChoice.unitTitle(unit, milliliters: selected.isMilliliters))"
            Button {
                onAdd(selected.ingredient(count: count, unit: unit))
                dismiss()
            } label: {
                Text(existing == nil ? "Add \(amount) \(selected.shortName.lowercased())" : "Save \(amount)")
                    .lineLimit(2)
            }
            .buttonStyle(.vessPrimary)
            .accessibilityIdentifier("ingredient.add")
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.vertical, VESSSpacing.sm)
            .background(VESSColor.card)
        }
    }

    private func step(_ unit: ServingOption) -> Double {
        unit.isBaseUnit ? 10 : 0.5
    }

    private func selectUnit(_ index: Int, units: [ServingOption]) {
        // Keep about the same weight when switching units.
        let grams = units[min(unitIndex, units.count - 1)].isBaseUnit ? count : count * units[unitIndex].amount
        unitIndex = index
        let unit = units[index]
        count = unit.isBaseUnit ? max(10, (grams / 10).rounded() * 10) : max(0.5, (grams / max(unit.amount, 1) * 2).rounded() / 2)
    }

    private func choose(_ choice: IngredientChoice) {
        // The amount and Add are what matter now, not the keyboard.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        // A food chosen for a pantry item is remembered for it.
        if let item = matchingItem, case .generic(let food) = choice.kind {
            var updated = item
            updated.genericFoodID = food.id
            try? store.save(updated)
            matchingItem = nil
            selected = IngredientChoice(kind: .pantry(updated, food))
        } else {
            selected = choice
        }
        unitIndex = 0
        // A pantry item starts at what's at home, when that's in grams or ml.
        if case .pantry(let item, _) = selected?.kind, let quantity = item.quantity, [.gram, .milliliter].contains(item.unit) {
            count = quantity
        } else {
            count = 100
        }
    }

    private func startWithExisting() {
        guard let existing, selected == nil else { return }
        selected = IngredientChoice(kind: .existing(existing))
        unitIndex = 0
        count = existing.grams ?? existing.quantity ?? 100
    }

    // MARK: Products

    private func searchProducts() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            products = []
            return
        }
        // Wait for a pause in typing.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        switch await lookup.searchOnline(trimmed) {
        case .success(let foods):
            products = foods.filter { $0.nutrition.canBeLogged }
            productsFailed = false
        case .failure:
            products = []
            productsFailed = true
        }
    }

    private var scanner: some View {
        IngredientBarcodeSheet { code in
            showsScanner = false
            Task {
                if case .success(let food) = await lookup.lookUp(barcode: code) {
                    choose(IngredientChoice(kind: .product(food)))
                } else {
                    query = code
                    source = .brands
                }
            }
        }
    }
}

/// A product barcode, for an ingredient.
private struct IngredientBarcodeSheet: View {
    let onCode: (String) -> Void

    @State private var controller = ScannerController()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BarcodeDataScanner(controller: controller, onCode: onCode)
                .ignoresSafeArea()
                .navigationTitle(Text("Scan a barcode"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                    }
                }
        }
    }
}
