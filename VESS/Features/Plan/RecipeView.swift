import PhotosUI
import SwiftUI

/// 08: a recipe, with its photo on top (R07's layout). Ingredients are
/// checked against the pantry; ones the user doesn't eat and that are
/// optional are struck through and left out of the nutrition. Planning and
/// logging use one serving; the servings stepper scales the amounts.
struct RecipeView: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let recipe: Recipe

    @State private var servings: Int
    @State private var showError = false
    @State private var edits = false
    @State private var confirmsDelete = false
    @State private var scrolledUnderBar = false

    private let calendar = Calendar.current

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: recipe.servings)
    }

    var body: some View {
        let now = AppClock.now
        let fit = store.profile.map { RecipeFit.check(recipe, preferences: $0.preferences, allergies: $0.allergies) }
        let skipped = fit?.skipped ?? []
        let cooked = recipe.without(skipped)
        let use = AIChef.pantryUse(cooked, pantry: store.inventory, now: now, calendar: calendar)
        let photo = recipe.photoImage(store: store)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                RecipePhotoHeader(photo: photo, onAddPhoto: recipe.origin == .discover ? nil : { (data: Data) in addPhoto(data) })

                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    recipe.detailKicker
                        .vessTextStyle(.labelCapsS)
                        .foregroundStyle(VESSColor.tertiaryText)
                    Text(recipe.name)
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let fit, !fit.fits {
                        VESSChipFlow(spacing: VESSSpacing.xs) {
                            ForEach(fit.reasons, id: \.self) { VESSTag(text: $0.text, tone: .warning) }
                        }
                    }
                }
                .padding(.horizontal, VESSSpacing.screenInset)

                VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                    RecipeStats(minutes: recipe.minutes, extraTime: recipe.extraTime, nutrition: cooked.nutrition)
                    RecipeMacroKey(nutrition: cooked.nutrition, includesProtein: false)
                }
                .padding(.horizontal, VESSSpacing.screenInset)

                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    // The stepper goes under the label at accessibility sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            ingredientsLabel
                            Spacer()
                            RecipeServingsStepper(servings: $servings)
                        }
                        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                            ingredientsLabel
                            RecipeServingsStepper(servings: $servings)
                        }
                    }
                    VESSRowGroup {
                        ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, ingredient in
                            RecipeIngredientRow(
                                ingredient: ingredient,
                                status: status(of: ingredient, skipped: skipped, use: use),
                                scale: Double(servings) / Double(max(recipe.servings, 1)),
                                now: now
                            )
                        }
                    }
                    .vessHairlineBottom()
                    RecipePantrySummary(use: use, scale: Double(servings) / Double(max(recipe.servings, 1)))
                }
                .padding(.horizontal, VESSSpacing.screenInset)

                RecipeMethod(steps: recipe.steps, tip: recipe.tip)
                    .padding(.horizontal, VESSSpacing.screenInset)

                // At accessibility sizes the buttons end the page instead of
                // covering half of it.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: VESSSpacing.sm) { actions(cooked, now: now) }
                        .padding(.horizontal, VESSSpacing.screenInset)
                }
            }
            .padding(.bottom, VESSSpacing.huge)
        }
        .onPhotoScrolled { scrolledUnderBar = $0 }
        // With a photo it runs under the bar; without one the page starts below it.
        .ignoresSafeArea(edges: photo == nil ? [] : .top)
        .modifier(RecipeTopFadeIfPhoto(hasPhoto: photo != nil, isScrolled: scrolledUnderBar))
        .vessScreenBackground(clipsUnderBar: false)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(Text(recipe.name))
        .toolbar {
            // The photo carries the screen; the bar shows only the back button.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            // The user's own and saved AI recipes can be changed or deleted.
            if recipe.origin != .discover {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { edits = true } label: { Label("Edit", systemImage: "pencil") }
                        Button(role: .destructive) { confirmsDelete = true } label: { Label("Delete recipe", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: VESSHitTarget.minimum, height: VESSHitTarget.minimum)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("recipe.more")
                }
            }
        }
        .fullScreenCover(isPresented: $edits) {
            RecipeEditorView(recipe: store.userRecipes.first { $0.id == recipe.id } ?? recipe)
        }
        .confirmationDialog("Delete \(recipe.name)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete recipe", role: .destructive) {
                do { try store.deleteRecipe(id: recipe.id); dismiss() } catch { showError = true }
            }
        } message: {
            Text("It's removed from this iPhone. Meals you logged from it stay in your log.")
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if !dynamicTypeSize.isAccessibilitySize {
                // Side by side, or one under the other when they don't fit.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VESSSpacing.sm) { actions(cooked, now: now) }
                    VStack(spacing: VESSSpacing.sm) { actions(cooked, now: now) }
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.vertical, VESSSpacing.sm)
                .background(VESSColor.background)
                .overlay(alignment: .top) { VESSHairline() }
            }
        }
        .vessErrorAlert(isPresented: $showError)
    }

    private var ingredientsLabel: some View {
        Text("Ingredients")
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.secondaryText)
    }

    /// A photo for one of the user's own recipes.
    private func addPhoto(_ data: Data) {
        do {
            try store.save(store.userRecipes.first { $0.id == recipe.id } ?? recipe, photo: data)
        } catch {
            showError = true
        }
    }

    @ViewBuilder
    private func actions(_ cooked: Recipe, now: Date) -> some View {
        Button { planForToday(cooked) } label: {
            Text(isPlannedToday
                 ? "Planned for \(now.formatted(.dateTime.weekday(.abbreviated)))"
                 : "Plan for \(now.formatted(.dateTime.weekday(.abbreviated)))")
        }
        .buttonStyle(.vessSecondary)
        .lineLimit(1)
        .disabled(isPlannedToday)
        .accessibilityIdentifier("recipe.plan")
        Button("Cook & log") { cookAndLog(cooked) }
            .lineLimit(1)
            .buttonStyle(.vessPrimary)
            .accessibilityIdentifier("recipe.log")
    }

    private func status(of ingredient: Recipe.Ingredient, skipped: [String], use: AIChef.PantryUse) -> RecipeIngredientRow.Status {
        if ingredient.isOptional, skipped.contains(where: { IngredientMatcher.ingredient(ingredient, contains: $0) }) { return .skipped }
        if let have = use.have.first(where: { $0.ingredient == ingredient }) {
            return have.item.expirationStatus(now: AppClock.now, calendar: calendar).needsAttention ? .useSoon(have.item) : .inPantry
        }
        if use.missing.contains(ingredient) { return .missing }
        if use.missingOptional.contains(ingredient) { return .missingOptional }
        return .plain
    }

    /// Already planned for today's slot.
    private var isPlannedToday: Bool {
        let today = calendar.startOfDay(for: AppClock.now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return store.plannedMeals(from: today, to: end).contains { $0.source == .recipe(recipe.id) }
    }

    // MARK: Actions

    /// Plans one serving for today's slot, replacing what was planned there.
    private func planForToday(_ cooked: Recipe) {
        let today = calendar.startOfDay(for: AppClock.now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        do {
            for existing in store.plannedMeals(from: today, to: end) where existing.mealType == cooked.mealType {
                try store.deletePlannedMeal(id: existing.id)
            }
            try store.save(PlannedMeal(candidate: .init(recipe: cooked), day: today, meal: cooked.mealType, now: AppClock.now, calendar: calendar))
            dismiss()
        } catch {
            showError = true
        }
    }

    /// Logs one serving now, with Undo. Nothing is added to the plan.
    private func cookAndLog(_ cooked: Recipe) {
        let meal = PlannedMeal(candidate: .init(recipe: cooked), day: AppClock.now, meal: cooked.mealType, now: AppClock.now, calendar: calendar)
        do {
            try PlanLogging.log(meal, store: store, undo: undo, calendar: calendar, markPlanned: false)
            dismiss()
        } catch {
            showError = true
        }
    }
}

extension View {
    /// On screens whose photo runs under the bar: a light fade over the
    /// photo, and once the photo has scrolled by (`isScrolled`), a solid
    /// scrim behind the bar, so no text shows behind the back button.
    func recipeTopFade(isScrolled: Bool) -> some View {
        overlay(alignment: .top) {
            GeometryReader { proxy in
                let bar = proxy.safeAreaInsets.top + VESSHitTarget.minimum
                VStack(spacing: 0) {
                    VESSColor.background
                        .frame(height: bar)
                        .opacity(isScrolled ? 1 : 0)
                    LinearGradient(colors: [VESSColor.background, VESSColor.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: VESSSpacing.xl)
                        .opacity(isScrolled ? 1 : 0)
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [VESSColor.background.opacity(0.7), VESSColor.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: bar + VESSSpacing.xl)
                        .opacity(isScrolled ? 0 : 1)
                }
                .animation(.easeOut(duration: 0.15), value: isScrolled)
                .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Whether a photo header has scrolled up under the bar.
    func onPhotoScrolled(_ action: @escaping (Bool) -> Void) -> some View {
        onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > RecipePhotoHeader.photoHeight - 160
        } action: { _, scrolled in
            action(scrolled)
        }
    }
}

extension Recipe {
    /// "DINNER · PESCATARIAN", "LUNCH · YOUR RECIPE", "DINNER · AI · PESCATARIAN".
    var detailKicker: Text {
        var parts: [Text] = [Text(category.title)]
        switch origin {
        case .discover: break
        case .user: parts.append(Text("Your recipe"))
        case .ai: parts.append(Text("AI"))
        }
        if origin != .user, let diet = dietLabel { parts.append(Text(diet)) }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }
}

// MARK: - Parts shared with the AI draft (R07) and the editor

/// The recipe photo, full width under the bar, fading into the canvas.
/// Without one, a short quiet strip under the bar with "Add photo".
struct RecipePhotoHeader: View {
    let photo: Image?
    var placeholder: Text?
    /// A photo the user picked, made smaller and without metadata.
    var onAddPhoto: ((Data) -> Void)?

    /// Height of the photo; the scrim covers the bar once this has scrolled by.
    static let photoHeight: CGFloat = 300

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = RecipePhotoHeader.photoHeight
    @State private var pickerItem: PhotosPickerItem?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let photo {
            ZStack(alignment: .bottom) {
                // The frame first, the photo inside it: a filled photo is
                // wider than the screen and would widen the whole page.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: min(height, 380))
                    .overlay { photo.resizable().scaledToFill() }
                    .clipped()
                LinearGradient(colors: [VESSColor.background.opacity(0), VESSColor.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: 96)
            }
            .accessibilityHidden(true)
        } else {
            // Stacked at accessibility sizes, so the button never squeezes.
            let isStacked = dynamicTypeSize.isAccessibilitySize
            let layout = isStacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.sm))
                : AnyLayout(HStackLayout(spacing: VESSSpacing.md))
            layout {
                Image(systemName: "fork.knife")
                    .font(.body)
                    .foregroundStyle(VESSColor.decorative)
                    .accessibilityHidden(true)
                (placeholder ?? Text("No photo yet"))
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !isStacked { Spacer(minLength: 0) }
                if onAddPhoto != nil {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Add photo", systemImage: "camera")
                            .vessTextStyle(.bodyS)
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(VESSColor.text)
                            .padding(.horizontal, VESSSpacing.sm)
                            .frame(minHeight: VESSHitTarget.minimum)
                            .background(Capsule().fill(VESSColor.fill).padding(.vertical, VESSSpacing.xxs))
                            .contentShape(Capsule())
                    }
                    .accessibilityIdentifier("recipe.addPhoto")
                }
            }
            .padding(.horizontal, VESSSpacing.md)
            .padding(.vertical, isStacked ? VESSSpacing.md : 0)
            .frame(minHeight: 76)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
            .padding(.horizontal, VESSSpacing.screenInset)
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        onAddPhoto?(PhotoPreparation.jpeg(from: data) ?? data)
                    }
                    pickerItem = nil
                }
            }
        }
    }
}

/// The fade and scrim only where a photo runs under the bar.
struct RecipeTopFadeIfPhoto: ViewModifier {
    let hasPhoto: Bool
    let isScrolled: Bool

    func body(content: Content) -> some View {
        if hasPhoto {
            content.recipeTopFade(isScrolled: isScrolled)
        } else {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        }
    }
}

/// "20 minutes · 560 kcal / serving · 38 g protein / serving".
struct RecipeStats: View {
    let minutes: Int
    var extraTime: String?
    let nutrition: NutritionFacts

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.md))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: VESSSpacing.md))
        layout {
            stat(Text("\(minutes)"), label: extraTime.map { Text("minutes + \($0)") } ?? Text("minutes"))
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            stat(Text(VESSFormat.calories(nutrition.calories)), label: Text("kcal / serving"))
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            stat(Text("\(VESSFormat.grams(nutrition.proteinGrams)) g"), label: Text("protein / serving"))
        }
        // Full width when stacked too, so the hairlines span the screen.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, VESSSpacing.md)
        .overlay(alignment: .top) { VESSHairline() }
        .vessHairlineBottom()
    }

    private func stat(_ value: Text, label: Text) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            value
                .vessTextStyle(.displayM)
                .foregroundStyle(VESSColor.text)
            label
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "● 42 g protein  ● 58 g carbs  ● 21 g fat", reported values only.
struct RecipeMacroKey: View {
    let nutrition: NutritionFacts
    /// Off where the stats above already show protein.
    var includesProtein = true

    var body: some View {
        let parts: [(nutrient: CoreNutrient, grams: Double, name: LocalizedStringResource, color: Color)] = [
            (.protein, nutrition.proteinGrams, "protein", VESSColor.protein),
            (.carbohydrates, nutrition.carbohydrateGrams, "carbs", VESSColor.carbs),
            (.fat, nutrition.fatGrams, "fat", VESSColor.fat),
        ].filter { nutrition.isReported($0.nutrient) && (includesProtein || $0.nutrient != .protein) }
        VESSChipFlow(spacing: VESSSpacing.lg) {
            ForEach(parts, id: \.nutrient) { part in
                HStack(spacing: VESSSpacing.xs) {
                    Circle().fill(part.color).frame(width: 6, height: 6).accessibilityHidden(true)
                    Text("\(VESSFormat.grams(part.grams)) g \(Text(part.name))")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
            }
        }
    }
}

/// "− 2 servings +".
struct RecipeServingsStepper: View {
    @Binding var servings: Int
    var range: ClosedRange<Int> = 1...12

    var body: some View {
        HStack(spacing: VESSSpacing.xs) {
            VESSIconButton(systemImage: "minus", label: "Fewer servings") { servings = max(range.lowerBound, servings - 1) }
                .disabled(servings <= range.lowerBound)
            Text("^[\(servings) serving](inflect: true)")
                .vessTextStyle(.bodyMStrong)
                .foregroundStyle(VESSColor.text)
                .monospacedDigit()
                .fixedSize()
            VESSIconButton(systemImage: "plus", label: "More servings") { servings = min(range.upperBound, servings + 1) }
                .disabled(servings >= range.upperBound)
        }
    }
}

/// An ingredient with its pantry tag and amount.
struct RecipeIngredientRow: View {
    enum Status: Equatable {
        case inPantry
        case useSoon(InventoryItem)
        case missing
        case missingOptional
        /// Optional and something the user doesn't eat.
        case skipped
        /// Salt, pepper, water.
        case plain
    }

    let ingredient: Recipe.Ingredient
    let status: Status
    var scale: Double = 1
    let now: Date

    @ScaledMetric(relativeTo: .body) private var amountWidth: CGFloat = 64
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let calendar = Calendar.current

    var body: some View {
        VESSRow(
            title: Text(ingredient.name).strikethrough(status == .skipped, color: VESSColor.tertiaryText),
            subtitle: status == .skipped ? Text("Skipped · you don't eat it") : nil
        ) {
            HStack(spacing: VESSSpacing.sm) {
                switch status {
                case .inPantry: VESSTag(text: Text("In pantry"))
                case .useSoon(let item): VESSTag(text: Text(RecipeText.useBy(item, now: now, calendar: calendar)), tone: .accent)
                case .missing: VESSTag(text: Text("Missing"), tone: .warning)
                case .missingOptional: VESSTag(text: Text("Missing · optional"), tone: .warning)
                case .skipped, .plain: EmptyView()
                }
                // A fixed column, so the tags line up whatever the amount.
                Text(ingredient.amountText(scale: scale) ?? "")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(status == .skipped ? VESSColor.tertiaryText : VESSColor.secondaryText)
                    .strikethrough(status == .skipped, color: VESSColor.tertiaryText)
                    // Under the name at accessibility sizes, so no column.
                    .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : amountWidth, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Numbered steps and the tip.
struct RecipeMethod: View {
    let steps: [String]
    var tip: String?

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Method")
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.md) {
                    Text("\(index + 1)")
                        .vessTextStyle(.numberS)
                        .foregroundStyle(VESSColor.text)
                        // Grows with Dynamic Type instead of clipping the number.
                        .frame(minWidth: 28, minHeight: 28)
                        .overlay(Circle().strokeBorder(VESSColor.divider))
                    Text(step)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let tip {
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text("Tip")
                        .vessTextStyle(.labelCapsS)
                        .foregroundStyle(VESSColor.tertiaryText)
                    Text(tip)
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, VESSSpacing.xs)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// "6 of 7 at home · uses 2 use-soon" and "Add to grocery list".
struct RecipePantrySummary: View {
    let use: AIChef.PantryUse
    var scale: Double = 1

    @Environment(LocalStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var added = false
    @State private var showError = false

    var body: some View {
        if use.countedTotal > 0 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VESSSpacing.sm) { summary; Spacer(minLength: 0); groceryButton }
                VStack(alignment: .leading, spacing: VESSSpacing.sm) { summary; groceryButton }
            }
            .padding(.top, VESSSpacing.sm)
            .vessErrorAlert(isPresented: $showError)
        }
    }

    private var summary: some View {
        Text(RecipeText.atHome(use))
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var groceryButton: some View {
        if !use.missing.isEmpty || !use.missingOptional.isEmpty {
            Button {
                do {
                    try RecipeGrocery.add(use.missing + use.missingOptional, servingsScale: scale, store: store)
                    added = true
                } catch {
                    showError = true
                }
            } label: {
                Label(added ? "On your grocery list" : "Add to grocery list", systemImage: added ? "checkmark" : "plus")
                    .vessTextStyle(.bodyMStrong)
            }
            .buttonStyle(.vessSecondary)
            // Its own width beside the summary; wraps at large text sizes.
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
            .disabled(added)
            .accessibilityIdentifier("recipe.addMissing")
        }
    }
}

/// Missing ingredients onto the grocery list, once each.
@MainActor
enum RecipeGrocery {
    static func add(_ ingredients: [Recipe.Ingredient], servingsScale: Double, store: LocalStore) throws {
        let listed = Set(store.groceryItems.filter { !$0.isDismissed && !$0.isChecked }.map(\.key))
        for ingredient in ingredients {
            let key = GroceryList.key(for: ingredient.name)
            guard !listed.contains(key) else { continue }
            let unit = ingredient.unit?.quantityUnit
            try store.save(GroceryItem(
                id: UUID(), key: key, name: ingredient.name,
                quantity: unit == nil ? nil : ingredient.quantity.map { $0 * servingsScale },
                unit: unit, aisle: nil, isChecked: false, isManual: true, isDismissed: false, createdAt: AppClock.now
            ))
        }
    }
}

extension RecipeText {
    /// "6 of 7 at home · uses 2 use-soon".
    static func atHome(_ use: AIChef.PantryUse) -> String {
        let base = String(localized: "\(use.atHomeCount) of \(use.countedTotal) at home")
        guard !use.useSoon.isEmpty else { return base }
        return String(localized: "\(base) · uses \(use.useSoon.count) use-soon")
    }
}
