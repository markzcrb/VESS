import SwiftUI
import UIKit

/// R06: what a new AI recipe should use and be. What is sent is only what's
/// on this sheet, the pantry list, and the diet and avoid list.
struct CreateWithAISheet: View {
    let meal: MealType
    let useSoon: [InventoryItem]
    /// Today's remaining protein, sent as the protein gap.
    var proteinGap: Double?
    /// A draft was saved to My recipes.
    var onSaved: () -> Void = {}

    typealias Goal = ChefGoal

    @Environment(LocalStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(AIConsentStore.self) private var consent
    @Environment(GenericFoodDatabase.self) private var foods
    @Environment(\.dismiss) private var dismiss

    @AppStorage("chef.remaining") private var remaining = -1
    @AppStorage("chef.remainingDay") private var remainingDay = ""
    @State private var isCreating = false
    @State private var failure: String?
    @State private var asksConsent = false
    @State private var signsIn = false

    @State private var mustUse: Set<UUID>
    @State private var chosenMeal: MealType
    @State private var goal: Goal?
    @State private var servings = 2
    @State private var onlyWhatIHave = false
    @State private var picksMore = false
    @State private var editsServings = false
    @State private var draft: Recipe?

    init(meal: MealType, useSoon: [InventoryItem], proteinGap: Double? = nil, onSaved: @escaping () -> Void = {}) {
        self.meal = meal
        self.useSoon = useSoon
        self.proteinGap = proteinGap
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
                            // A chip like the others, so it grows with them.
                            VESSChip(title: "+ Pick more", isSelected: false) { picksMore = true }
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

                    if let failure {
                        Text(failure)
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(VESSSpacing.md)
                            .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
                            .accessibilityIdentifier("create.failure")
                    }

                    Text("Sends your pantry list, diet and avoid list and these choices to \(AIProcessor.displayName) through VESS's server. Nothing else from your log. You review the recipe before it's saved.")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.bottom, VESSSpacing.xl)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: VESSSpacing.xs) {
                    Button(action: create) {
                        if isCreating {
                            HStack(spacing: VESSSpacing.xs) {
                                ProgressView().tint(VESSColor.onAccent)
                                Text("Writing a recipe…")
                            }
                        } else {
                            Text("Create recipe")
                        }
                    }
                    .buttonStyle(.vessPrimary)
                    // None left today: nothing to try until it resets.
                    .disabled(isCreating || (remaining == 0 && remainingDay == AIQuota.serverDay(AppClock.now)))
                    .accessibilityIdentifier("create.go")
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.vertical, VESSSpacing.sm)
                .background(VESSColor.card)
            }
            .vessAIConsent(.chef, isPresented: $asksConsent) { create() }
            .sheet(isPresented: $signsIn) { AISignInSheet() }
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

    /// Consent once, an account, then one request. The draft is built and
    /// checked on this iPhone before it's shown.
    private func create() {
        guard !isCreating else { return }
        guard consent.isGranted(.chef) else {
            asksConsent = true
            return
        }
        guard account.isSignedIn else {
            signsIn = true
            return
        }
        guard let profile = store.profile else { return }
        let now = AppClock.now
        let calendar = Calendar.current
        let pantry = store.inventory
        let request = ChefRequest.make(
            pantry: pantry, mustUse: pantry.filter { mustUse.contains($0.id) }, meal: chosenMeal, goal: goal,
            servings: servings, onlyWhatIHave: onlyWhatIHave, preferences: profile.preferences, allergies: profile.allergies,
            proteinGapGrams: proteinGap, locale: CoachRequest.locale, now: now, calendar: calendar
        )
        failure = nil
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                await foods.load()
                let response: ChefResponse = try await account.callFunction("chef", body: request)
                if let left = response.remaining { setRemaining(left) }
                let outcome = ChefDraftBuilder.build(
                    response, meal: chosenMeal, preferences: profile.preferences, allergies: profile.allergies, pantry: pantry,
                    search: { foods.search($0, limit: 1).first }, food: { foods.food(ndb: $0) }
                )
                switch outcome {
                case .draft(let built):
                    draft = built.recipe
                case .conflict:
                    failure = String(localized: "That draft used something you avoid. Try another.")
                }
            } catch {
                failure = Self.message(for: BackendError.from(error), now: now)
                if BackendError.from(error) == .dailyLimit { setRemaining(0) }
                if BackendError.from(error) == .notSignedIn { signsIn = true }
            }
        }
    }

    private func setRemaining(_ value: Int) {
        remaining = value
        remainingDay = AIQuota.serverDay(AppClock.now)
    }

    /// Calm words for what went wrong.
    static func message(for error: BackendError, now: Date) -> String {
        switch error {
        case .dailyLimit: String(localized: "No AI recipes left today. Back tomorrow. \(AIQuotaText.resets(after: now))")
        case .upstream: String(localized: "AI Chef couldn't write a recipe just now. This one didn't count; try again.")
        case .notConfigured: String(localized: "AI Chef isn't available right now.")
        case .offline: String(localized: "You're offline. AI Chef needs a connection; everything else works without one.")
        case .notSignedIn: String(localized: "Sign in to use AI Chef.")
        default: String(localized: "Something went wrong. Try again.")
        }
    }
}

private struct ChoosingIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

/// "Resets at 02:00": when the AI limits count again (00:00 UTC), in the
/// user's time.
enum AIQuotaText {
    static func resets(after now: Date) -> String {
        String(localized: "Resets at \(AIQuota.resetTime(after: now).formatted(date: .omitted, time: .shortened)).")
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
            .safeAreaInset(edge: .bottom) {
                Button("Done") { dismiss() }
                    .buttonStyle(.vessPrimary)
                    .padding(.horizontal, VESSSpacing.screenInset)
                    .padding(.vertical, VESSSpacing.sm)
                    .background(VESSColor.card)
            }
            .background(VESSColor.card)
            .vessDetailTitle("Must use")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
            }
        }
        // Full height: a medium sheet is drawn scaled down, below 44 pt targets.
        .presentationDetents([.large])
        .presentationBackground(VESSColor.card)
    }
}

/// R07: an AI draft, not saved until the user saves it. Nutrition is
/// recalculated on the device from USDA data, never taken from the AI.
struct AIRecipeReviewView: View {
    @State var draft: Recipe
    let summary: String
    let onFinished: () -> Void
    var onSaved: () -> Void = {}
    let onTryAnother: () -> Void

    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var servings: Int
    @State private var draftPhoto: Data?
    @State private var choosingIndex: Int?
    @Environment(GenericFoodDatabase.self) private var foods
    @State private var scrolledUnderBar = false
    @State private var edits = false
    @State private var showError = false

    private let calendar = Calendar.current

    init(draft: Recipe, summary: String, onFinished: @escaping () -> Void, onSaved: @escaping () -> Void = {}, onTryAnother: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.summary = summary
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
                    RecipePhotoHeader(
                        photo: draftPhoto.flatMap(UIImage.init(data:)).map(Image.init(uiImage:)),
                        placeholder: Text("No photo yet · add one after you cook it"),
                        onAddPhoto: { draftPhoto = $0 }
                    )

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
                        RecipeMacroKey(nutrition: draft.nutrition, includesProtein: false)
                        if draft.ingredients.contains(where: { $0.per100 == nil }) {
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
                            ForEach(Array(draft.ingredients.enumerated()), id: \.offset) { index, ingredient in
                                if ingredient.per100 == nil {
                                    // "No nutrition data · Choose food".
                                    Button { choosingIndex = index } label: {
                                        VESSListRow(title: Text(ingredient.name), subtitle: Text("No nutrition data · Choose food"), value: Text(ingredient.amountText() ?? ""))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("draft.chooseFood")
                                } else {
                                    RecipeIngredientRow(
                                        ingredient: ingredient, status: status(of: ingredient, use: use),
                                        scale: Double(servings) / Double(max(draft.servings, 1)), now: now
                                    )
                                }
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
            .onPhotoScrolled { scrolledUnderBar = $0 }
            .ignoresSafeArea(edges: draftPhoto == nil ? [] : .top)
            .modifier(RecipeTopFadeIfPhoto(hasPhoto: draftPhoto != nil, isScrolled: scrolledUnderBar))
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
            .sheet(item: Binding(get: { choosingIndex.map(ChoosingIndex.init) }, set: { choosingIndex = $0?.index })) { choosing in
                AddIngredientSheet(existing: draft.ingredients[choosing.index]) { chosen in
                    guard draft.ingredients.indices.contains(choosing.index) else { return }
                    var ingredient = chosen
                    // Keep the draft's name and amount; take the food's values.
                    ingredient.name = draft.ingredients[choosing.index].name
                    draft.ingredients[choosing.index] = ingredient
                    draft = RecipeDerivation.complete(draft) { foods.food(ndb: $0)?.per100g }.recipe
                }
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
        Button("Save recipe", action: save)
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
            try store.save(saved, photo: draftPhoto)
            dismiss()
            onSaved()
        } catch {
            showError = true
        }
    }
}
