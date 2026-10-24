import SwiftUI

/// R06: what a new AI recipe should use and be. What is sent is only what's
/// on this sheet, the pantry list, and the diet and avoid list.
struct CreateWithAISheet: View {
    let meal: MealType
    let useSoon: [InventoryItem]
    /// A draft was saved to My recipes.
    var onSaved: () -> Void = {}

    enum Goal: CaseIterable {
        case highProtein, lighter, quick, comfort

        var title: LocalizedStringResource {
            switch self {
            case .highProtein: "High-protein"
            case .lighter: "Lighter"
            case .quick: "Quick (≤ 20 min)"
            case .comfort: "Comfort"
            }
        }
    }

    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var mustUse: Set<UUID>
    @State private var chosenMeal: MealType
    @State private var goal: Goal?
    @State private var servings = 2
    @State private var onlyWhatIHave = false
    @State private var picksMore = false
    @State private var editsServings = false
    @State private var draft: Recipe?

    init(meal: MealType, useSoon: [InventoryItem], onSaved: @escaping () -> Void = {}) {
        self.meal = meal
        self.useSoon = useSoon
        self.onSaved = onSaved
        _mustUse = State(initialValue: Set(useSoon.prefix(2).map(\.id)))
        _chosenMeal = State(initialValue: meal)
    }

    var body: some View {
        let profile = store.profile
        let pantry = store.inventory.filter { $0.status == .available }
        let shown = (useSoon + pantry.filter { mustUse.contains($0.id) && !useSoon.contains($0) })
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    section("Must use") {
                        VESSChipFlow(spacing: VESSSpacing.xs) {
                            ForEach(shown, id: \.id) { item in
                                VESSChip(title: LocalizedStringResource(stringLiteral: item.name), isSelected: mustUse.contains(item.id)) {
                                    mustUse.formSymmetricDifference([item.id])
                                }
                            }
                            Button { picksMore = true } label: {
                                Text("+ Pick more")
                                    .vessTextStyle(.bodyS)
                                    .foregroundStyle(VESSColor.text)
                                    .padding(.horizontal, VESSSpacing.sm + 2)
                                    .frame(minHeight: VESSHitTarget.minimum)
                                    .background(Capsule().strokeBorder(VESSColor.divider).padding(.vertical, VESSSpacing.xxs))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("create.pickMore")
                        }
                    }
                    section("Meal") {
                        VESSChipFlow(spacing: VESSSpacing.xs) {
                            ForEach(MealType.allCases, id: \.self) { option in
                                VESSChip(title: option.title, isSelected: chosenMeal == option) { chosenMeal = option }
                            }
                        }
                    }
                    section("Goal") {
                        VESSChipFlow(spacing: VESSSpacing.xs) {
                            ForEach(Goal.allCases, id: \.self) { option in
                                VESSChip(title: option.title, isSelected: goal == option) { goal = goal == option ? nil : option }
                            }
                        }
                    }

                    VESSRowGroup {
                        Button { editsServings = true } label: {
                            VESSListRow(title: Text("Servings"), value: Text("\(servings)"))
                        }
                        .buttonStyle(.plain)
                        Toggle(isOn: $onlyWhatIHave) {
                            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                                Text("Only what I have")
                                    .vessTextStyle(.bodyM)
                                    .foregroundStyle(VESSColor.text)
                                Text(onlyWhatIHave ? "Nothing to buy" : "Allow 1–2 missing items if needed")
                                    .vessTextStyle(.bodyS)
                                    .foregroundStyle(VESSColor.secondaryText)
                            }
                        }
                        .toggleStyle(VESSToggleStyle())
                        .frame(minHeight: VESSSize.rowHeight)
                        .accessibilityIdentifier("create.onlyWhatIHave")
                        VESSListRow(
                            title: Text("Diet and avoid"),
                            subtitle: profile.map { Text(RecipeText.fitsYou($0).replacingOccurrences(of: String(localized: "Fits you: "), with: "")) },
                            value: Text("Always"), showsChevron: false
                        )
                    }
                    .vessHairlineBottom()

                    Text("Sends your pantry list, diet and avoid list and these choices to \(AIProcessor.displayName) through VESS's server. Nothing else from your log. You review the recipe before it's saved.")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.bottom, VESSSpacing.xl)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Create recipe", action: create)
                    .buttonStyle(.vessPrimary)
                    .padding(.horizontal, VESSSpacing.screenInset)
                    .padding(.vertical, VESSSpacing.sm)
                    .background(VESSColor.card)
                    .accessibilityIdentifier("create.go")
            }
            .background(VESSColor.card)
            .vessDetailTitle("Create with AI")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
            }
            .sheet(isPresented: $picksMore) { PantryPicker(selection: $mustUse) }
            .sheet(isPresented: $editsServings) {
                NumberEditSheet(title: "Servings", unit: "", value: Double(servings), range: 1...8, step: 1) { servings = Int($0) }
                    .presentationDetents([.height(320)])
            }
            .fullScreenCover(item: $draft) { recipe in
                AIRecipeReviewView(draft: recipe, summary: summary, onFinished: { dismiss() }, onSaved: { dismiss(); onSaved() }, onTryAnother: create)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
        .presentationBackground(VESSColor.card)
    }

    /// "Made from your pantry for a high-protein dinner."
    private var summary: String {
        let mealName = String(localized: chosenMeal.title).lowercased()
        guard let goal else { return String(localized: "Made from your pantry for \(mealName).") }
        return String(localized: "Made from your pantry for a \(String(localized: goal.title).lowercased()) \(mealName).")
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text(title)
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
            content()
        }
    }

    /// The server call comes with the AI Chef function; until then debug
    /// builds show a fixed draft.
    private func create() {
        #if DEBUG
        draft = MockData.chefDraft(servings: servings, meal: chosenMeal)
        #endif
    }
}

/// "+ Pick more": any pantry item as a must-use.
private struct PantryPicker: View {
    @Binding var selection: Set<UUID>

    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VESSRowGroup {
                    ForEach(store.inventory.filter { $0.status == .available }, id: \.id) { item in
                        Button { selection.formSymmetricDifference([item.id]) } label: {
                            HStack {
                                Text(item.name)
                                    .vessTextStyle(.bodyM)
                                    .foregroundStyle(VESSColor.text)
                                Spacer()
                                if selection.contains(item.id) {
                                    Image(systemName: "checkmark").foregroundStyle(VESSColor.text)
                                }
                            }
                            .frame(minHeight: VESSSize.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selection.contains(item.id) ? .isSelected : [])
                    }
                }
                .vessHairlineBottom()
                .padding(.horizontal, VESSSpacing.screenInset)
            }
            .background(VESSColor.card)
            .vessDetailTitle("Must use")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(VESSColor.card)
    }
}

/// R07: an AI draft, not saved until the user saves it. Nutrition is
/// recalculated on the device from USDA data, never taken from the AI.
struct AIRecipeReviewView: View {
    @State var draft: Recipe
    let summary: String
    var isPartial = false
    let onFinished: () -> Void
    var onSaved: () -> Void = {}
    let onTryAnother: () -> Void

    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var servings: Int
    @State private var edits = false
    @State private var showError = false

    private let calendar = Calendar.current

    init(draft: Recipe, summary: String, isPartial: Bool = false, onFinished: @escaping () -> Void, onSaved: @escaping () -> Void = {}, onTryAnother: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.summary = summary
        self.isPartial = isPartial
        self.onFinished = onFinished
        self.onSaved = onSaved
        self.onTryAnother = onTryAnother
        _servings = State(initialValue: draft.servings)
    }

    var body: some View {
        let now = AppClock.now
        let use = AIChef.pantryUse(draft, pantry: store.inventory, now: now, calendar: calendar)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    RecipePhotoHeader(photo: nil, placeholder: Text("No photo yet · add one after you cook it"))

                    VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                        draftKicker
                            .vessTextStyle(.labelCapsS)
                            .foregroundStyle(VESSColor.tertiaryText)
                        Text(draft.name)
                            .vessTextStyle(.editorialL)
                            .foregroundStyle(VESSColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.horizontal, VESSSpacing.screenInset)

                    banner
                        .padding(.horizontal, VESSSpacing.screenInset)

                    VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                        RecipeStats(minutes: draft.minutes, extraTime: draft.extraTime, nutrition: draft.nutrition)
                        RecipeMacroKey(nutrition: draft.nutrition)
                        if isPartial {
                            Text("Partial: some ingredients have no nutrition data.")
                                .vessTextStyle(.caption)
                                .foregroundStyle(VESSColor.secondaryText)
                        }
                    }
                    .padding(.horizontal, VESSSpacing.screenInset)

                    VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                        ViewThatFits(in: .horizontal) {
                            HStack { ingredientsLabel; Spacer(); RecipeServingsStepper(servings: $servings, range: 1...8) }
                            VStack(alignment: .leading, spacing: VESSSpacing.xs) { ingredientsLabel; RecipeServingsStepper(servings: $servings, range: 1...8) }
                        }
                        VESSRowGroup {
                            ForEach(Array(draft.ingredients.enumerated()), id: \.offset) { _, ingredient in
                                RecipeIngredientRow(
                                    ingredient: ingredient, status: status(of: ingredient, use: use),
                                    scale: Double(servings) / Double(max(draft.servings, 1)), now: now
                                )
                            }
                        }
                        .vessHairlineBottom()
                        RecipePantrySummary(use: use, scale: Double(servings) / Double(max(draft.servings, 1)))
                    }
                    .padding(.horizontal, VESSSpacing.screenInset)

                    RecipeMethod(steps: draft.steps, tip: draft.tip)
                        .padding(.horizontal, VESSSpacing.screenInset)

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: VESSSpacing.sm) { saveButton; discardButton }
                            .padding(.horizontal, VESSSpacing.screenInset)
                    }
                }
                .padding(.bottom, VESSSpacing.huge)
            }
            .ignoresSafeArea(edges: .top)
            .recipeTopFade()
            .vessScreenBackground(clipsUnderBar: false)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(Text(draft.name))
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                ToolbarItem(placement: .topBarLeading) {
                    VESSIconButton(systemImage: "chevron.left", label: "Back") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !dynamicTypeSize.isAccessibilitySize {
                    // Discard as wide as its word; Save takes the rest.
                    HStack(spacing: VESSSpacing.sm) {
                        discardButton.fixedSize(horizontal: true, vertical: false)
                        saveButton
                    }
                    .padding(.horizontal, VESSSpacing.screenInset)
                    .padding(.vertical, VESSSpacing.sm)
                    .background(VESSColor.background)
                    .overlay(alignment: .top) { VESSHairline() }
                }
            }
            .fullScreenCover(isPresented: $edits) {
                RecipeEditorView(recipe: draft) { draft = $0 }
            }
            .vessErrorAlert(isPresented: $showError)
        }
    }

    private var ingredientsLabel: some View {
        Text("Ingredients")
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.secondaryText)
    }

    /// "DINNER · AI DRAFT · PESCATARIAN".
    private var draftKicker: Text {
        if let diet = draft.dietLabel {
            return Text("\(Text(draft.category.title)) · AI draft · \(Text(diet))")
        }
        return Text("\(Text(draft.category.title)) · AI draft")
    }

    /// "AI DRAFT · NOT SAVED YET" with Edit and Try another.
    private var banner: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            Text("AI draft · not saved yet")
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.accent)
            Text(bannerText)
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: VESSSpacing.xl) {
                Button { edits = true } label: {
                    Text("Edit").vessTextStyle(.labelCapsLink).foregroundStyle(VESSColor.accent)
                        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("draft.edit")
                Button { dismiss(); onTryAnother() } label: {
                    Text("Try another").vessTextStyle(.labelCapsLink).foregroundStyle(VESSColor.accent)
                        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("draft.tryAnother")
            }
        }
        .padding(VESSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VESSColor.tintLink, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.strokeLink))
    }

    private var bannerText: String {
        let fits = store.profile.map { RecipeText.fitsYou($0).replacingOccurrences(of: String(localized: "Fits you: "), with: "") } ?? ""
        let fitLine = fits.isEmpty ? "" : String(localized: "Fits your diet: \(fits.replacingOccurrences(of: " · ", with: ", ")). ")
        return String(localized: "\(summary) \(fitLine)Check amounts and steps; nutrition is recalculated from USDA data, not taken from the AI.")
    }

    private var discardButton: some View {
        Button("Discard") { dismiss(); onFinished() }
            .buttonStyle(.vessSecondary)
            .accessibilityIdentifier("draft.discard")
    }

    private var saveButton: some View {
        Button("Save to My recipes", action: save)
            .buttonStyle(.vessPrimary)
            .accessibilityIdentifier("draft.save")
    }

    private func status(of ingredient: Recipe.Ingredient, use: AIChef.PantryUse) -> RecipeIngredientRow.Status {
        if let have = use.have.first(where: { $0.ingredient == ingredient }) {
            return have.item.expirationStatus(now: AppClock.now, calendar: calendar).needsAttention ? .useSoon(have.item) : .inPantry
        }
        if use.missing.contains(ingredient) { return .missing }
        if use.missingOptional.contains(ingredient) { return .missingOptional }
        return .plain
    }

    private func save() {
        var saved = draft
        saved.origin = .ai
        saved.createdAt = AppClock.now
        do {
            try store.save(saved)
            dismiss()
            onSaved()
        } catch {
            showError = true
        }
    }
}

#if DEBUG
extension MockData {
    /// R07's draft, for debug builds until the AI Chef function is wired:
    /// made from the demo pantry, nutrition calculated from USDA values.
    static func chefDraft(servings: Int, meal: MealType) -> Recipe {
        func usda(_ name: String, _ ndb: String, grams: Double, quantity: Double, unit: Recipe.Unit, allergens: Set<Allergen> = [], optional: Bool = false) -> Recipe.Ingredient {
            Recipe.Ingredient(name: name, key: name.lowercased(), quantity: quantity, unit: unit, grams: grams, allergens: allergens,
                              source: .usda(ndb: ndb), per100: genericFoods[ndb]?.per100g, isOptional: optional)
        }
        let ingredients = [
            usda("Jasmine rice", "20044", grams: 150, quantity: 150, unit: .gram),
            usda("Bok choy", "11116", grams: 250, quantity: 2, unit: .piece),
            usda("Baby spinach", "11457", grams: 100, quantity: 100, unit: .gram),
            usda("Eggs", "01123", grams: 200, quantity: 4, unit: .piece, allergens: [.eggs]),
            usda("White miso", "16112", grams: 17, quantity: 1, unit: .tablespoon, allergens: [.soy]),
            usda("Sesame oil", "04058", grams: 4.5, quantity: 1, unit: .teaspoon, allergens: [.sesame]),
            usda("Spring onions", "11291", grams: 30, quantity: 2, unit: .piece, optional: true),
        ]
        let base = Recipe(
            id: "draft-\(UUID().uuidString)", name: "Bok choy, spinach and miso egg rice", category: .dinner, minutes: 20, extraTime: nil,
            servings: 2, nutrition: .zero, ingredients: ingredients,
            steps: [
                "Rinse and cook the rice. Meanwhile halve the bok choy.",
                "Whisk miso with a splash of hot water and the sesame oil.",
                "Fry the eggs. Wilt bok choy and spinach in the same pan, 2 minutes.",
                "Spoon greens and eggs over rice, drizzle the miso. Top with spring onions if you have them.",
            ],
            tip: nil, dietTags: [], tags: [], highProtein: false, contains: [], allergens: [], photo: nil, origin: .ai, createdAt: nil
        )
        var recipe = RecipeDerivation.complete(base) { genericFoods[$0]?.per100g }.recipe
        recipe.servings = servings
        if servings != 2 {
            recipe.ingredients = recipe.ingredients.map { ingredient in
                var scaled = ingredient
                scaled.quantity = ingredient.quantity.map { $0 * Double(servings) / 2 }
                scaled.grams = ingredient.grams.map { $0 * Double(servings) / 2 }
                return scaled
            }
        }
        return recipe
    }
}
#endif
