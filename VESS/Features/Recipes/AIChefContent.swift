import SwiftUI

/// R05: what to cook from what's at home. Recipes from Discover and My
/// recipes that fit, ranked by the use-soon items they use, then how much
/// is at home, then today's remaining targets (`AIChef`). The best match
/// shows what's at home and what's missing; "Create with AI" makes a new
/// recipe from the pantry (R06).
struct AIChefContent: View {
    /// A draft was saved: show it in My recipes.
    var onSaved: () -> Void = {}

    @Environment(LocalStore.self) private var store
    @Environment(RecipeCatalog.self) private var catalog
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    enum Sort: CaseIterable {
        case best, quickest, protein

        var title: LocalizedStringResource {
            switch self {
            case .best: "Best match"
            case .quickest: "Quickest"
            case .protein: "Most protein"
            }
        }
    }

    @State private var mealFilterOn = true
    @State private var under30 = false
    @State private var highProtein = false
    @State private var usesUseSoon = false
    @State private var sort: Sort = .best
    @State private var createsWithAI = false
    @AppStorage("chef.remaining") private var chefRemaining = -1
    @AppStorage("chef.remainingDay") private var chefRemainingDay = ""
    @Environment(AccountStore.self) private var account
    @Environment(PlanStore.self) private var planStore
    @State private var swapped: Recipe?

    /// Matches shown: the best as a card, the rest as rows.
    static let shownMatches = 6

    private let calendar = Calendar.current

    var body: some View {
        if let profile = store.profile {
            let now = AppClock.now
            let pantry = store.inventory.filter { $0.status == .available }
            let useSoon = pantry
                .filter { item in
                    let status = item.expirationStatus(now: now, calendar: calendar)
                    if case .expired = status { return false }
                    return status.needsAttention
                }
                .sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
            let meal = nextMeal(profile: profile, now: now)
            let remaining = Self.remaining(profile: profile, entries: store.foodEntries(on: now, calendar: calendar))
            let matches = sorted(AIChef.rank(
                Self.withoutCopies(catalog.recipes, own: store.userRecipes),
                preferences: profile.preferences, allergies: profile.allergies,
                pantry: store.inventory, remaining: remaining,
                filters: .init(meal: mealFilterOn ? meal : nil, under30Minutes: under30, highProtein: highProtein, usesUseSoon: usesUseSoon),
                now: now, calendar: calendar
            ))

            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text("Cook what you have.")
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(pantry.isEmpty
                         ? "Add what's in your fridge and cupboards, and AI Chef suggests recipes that use it."
                         : "From ^[\(pantry.count) item](inflect: true) in your pantry. Use-soon first, then the most you already have.")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if pantry.isEmpty {
                    NavigationLink { PantryView() } label: { Text("Open Pantry") }
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("chef.openPantry")
                } else {
                    if !useSoon.isEmpty { useSoonCard(useSoon, now: now) }
                    filterChips(meal: meal)
                    if matches.isEmpty {
                        Text("Nothing fits these filters with what's at home. Try fewer filters, or create a recipe with AI.")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        bestMatches(matches)
                    }
                }

                createCard(profile: profile, remaining: remaining)
            }
            .sheet(isPresented: $createsWithAI) {
                CreateWithAISheet(meal: meal, useSoon: useSoon, proteinGap: Self.remaining(profile: profile, entries: store.foodEntries(on: AppClock.now, calendar: calendar)).proteinGrams, onSaved: onSaved)
            }
            .navigationDestination(item: $swapped) { RecipeView(recipe: $0) }
        }
    }

    // MARK: Parts

    /// "USE SOON · 3" with each item and when it's due.
    private func useSoonCard(_ items: [InventoryItem], now: Date) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            // Side by side, or the link under the label at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack { useSoonLabel(items.count); Spacer(); pantryLink }
                VStack(alignment: .leading, spacing: 0) { useSoonLabel(items.count); pantryLink }
            }
            VESSChipFlow(spacing: VESSSpacing.xs) {
                ForEach(items, id: \.id) { item in
                    VESSTag(text: Text("\(item.name) · \(Self.when(item, now: now, calendar: calendar))"), tone: .accent)
                }
            }
        }
        .padding(VESSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider))
    }

    private func useSoonLabel(_ count: Int) -> some View {
        Text("Use soon · \(count)")
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize()
    }

    private var pantryLink: some View {
        NavigationLink { PantryView() } label: {
            Text("Pantry")
                .vessTextStyle(.labelCapsLink)
                .foregroundStyle(VESSColor.accent)
                .fixedSize()
                .frame(minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "tomorrow", "Thu", "today".
    static func when(_ item: InventoryItem, now: Date, calendar: Calendar) -> String {
        switch item.expirationStatus(now: now, calendar: calendar) {
        case .today: String(localized: "today")
        case .tomorrow: String(localized: "tomorrow")
        default: item.expirationDate?.formatted(.dateTime.weekday(.abbreviated)) ?? ""
        }
    }

    private func filterChips(meal: MealType) -> some View {
        VESSBleedingRow {
            HStack(spacing: VESSSpacing.xs) {
                VESSChip(title: meal.title, isSelected: mealFilterOn) { mealFilterOn.toggle() }
                VESSChip(title: "Under 30\u{00A0}min", isSelected: under30) { under30.toggle() }
                VESSChip(title: "High-protein", isSelected: highProtein) { highProtein.toggle() }
                VESSChip(title: "Uses use-soon", isSelected: usesUseSoon) { usesUseSoon.toggle() }
            }
        }
    }

    private func bestMatches(_ matches: [AIChef.Match]) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            HStack {
                Text("Best matches")
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.secondaryText)
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: VESSSpacing.xxs) {
                        Text("Sort")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .frame(minHeight: VESSHitTarget.minimum)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("chef.sort")
            }

            if let best = matches.first {
                NavigationLink { RecipeView(recipe: original(best)) } label: {
                    VESSRecipeCard(
                        size: .large, photo: best.recipe.photoImage(store: store),
                        kicker: kicker(best.recipe), title: Text(best.recipe.name), meta: best.recipe.metaLine,
                        badges: [badge(best)]
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chef.best")
                haveMissing(best)
            }

            VESSRowGroup {
                ForEach(matches.dropFirst().prefix(Self.shownMatches - 1)) { match in
                    NavigationLink { RecipeView(recipe: original(match)) } label: {
                        VESSRecipeCard(
                            size: .row, photo: match.recipe.photoImage(store: store),
                            kicker: kicker(match.recipe), title: Text(match.recipe.name), meta: match.recipe.metaLine,
                            badges: [badge(match)]
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .vessHairlineBottom()
        }
    }

    /// "DINNER · DISCOVER", "DINNER · MY RECIPES".
    private func kicker(_ recipe: Recipe) -> Text {
        Text("\(Text(recipe.category.title)) · \(Text(recipe.origin == .discover ? "Discover" : "My recipes"))")
    }

    /// "6 OF 8 AT HOME · USES 2 USE-SOON".
    private func badge(_ match: AIChef.Match) -> VESSRecipeBadge {
        VESSRecipeBadge(text: Text(RecipeText.atHome(match.pantry)), tone: match.pantry.useSoon.isEmpty ? .neutral : .accent)
    }

    /// The recipe as stored, for its detail (which skips what the user
    /// doesn't eat itself).
    private func original(_ match: AIChef.Match) -> Recipe {
        catalog.recipe(id: match.recipe.id) ?? store.userRecipes.first { $0.id == match.recipe.id } ?? match.recipe
    }

    /// At home and missing for the best match, with grocery and swaps.
    private func haveMissing(_ match: AIChef.Match) -> some View {
        let have = match.pantry.have.map { $0.ingredient.name.lowercased() }
        let missing = (match.pantry.missing + match.pantry.missingOptional).map { $0.name.lowercased() }
        return VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            if !have.isEmpty {
                Label { Text("At home: \(have.joined(separator: ", "))") } icon: { Image(systemName: "checkmark") }
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !missing.isEmpty {
                Label { Text("Missing: \(missing.joined(separator: ", "))") } icon: { Image(systemName: "plus") }
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ChefGroceryLink(missing: match.pantry.missing + match.pantry.missingOptional)
            }
            ForEach(match.swaps, id: \.missing.name) { swap in
                Button {
                    swapped = AIChef.swapping(
                        swap.missing,
                        from: AIChef.swapGroups.flatMap(\.self).first { IngredientMatcher.ingredient(swap.missing, contains: $0.name) } ?? .init(name: swap.missing.name, contents: [], allergens: []),
                        to: AIChef.swapGroups.flatMap(\.self).first { $0.name == swap.replacement } ?? .init(name: swap.replacement, contents: [], allergens: []),
                        in: original(match)
                    )
                } label: {
                    Text("Swap \(Self.swapName(swap.missing)) for \(swap.replacement)")
                        .vessTextStyle(.labelCapsLink)
                        .foregroundStyle(VESSColor.accent)
                        .frame(minHeight: VESSHitTarget.minimum, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chef.swap")
            }
        }
        .padding(VESSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider))
    }

    /// "cod" for "Cod fillets, skinless".
    static func swapName(_ ingredient: Recipe.Ingredient) -> String {
        AIChef.swapGroups.flatMap(\.self).first { IngredientMatcher.ingredient(ingredient, contains: $0.name) }?.name ?? ingredient.name.lowercased()
    }

    /// "NOTHING QUITE RIGHT?" and Create with AI.
    private func createCard(profile: UserProfile, remaining: AIChef.Remaining) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text("Nothing quite right?")
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.accent)
            Text("Make a new recipe from what you have.")
                .vessTextStyle(.bodyMStrong)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(remaining.proteinGrams > 0
                 ? "Uses your pantry, diet and avoid list, and today's protein gap (\(VESSFormat.grams(remaining.proteinGrams))\u{00A0}g left). You check it before saving."
                 : "Uses your pantry, diet and avoid list. You check it before saving.")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Create with AI") { createsWithAI = true }
                .buttonStyle(.vessPrimary)
                .padding(.top, VESSSpacing.xs)
                .accessibilityIdentifier("chef.create")
            // "8 left today · Resets at 02:00", once known and signed in.
            if account.isSignedIn, chefRemaining >= 0, chefRemainingDay == AIQuota.serverDay(AppClock.now) {
                Text("\(chefRemaining) left today · \(AIQuotaText.resets(after: AppClock.now))")
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.secondaryText)
                    .accessibilityIdentifier("chef.remaining")
            }
        }
        .padding(VESSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VESSColor.tintLink, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.strokeLink))
        // Today's count before the first request; offline or signed out, none.
        .task(id: account.isSignedIn) { await loadRemaining() }
    }

    private func loadRemaining() async {
        guard account.isSignedIn else { return }
        let limit = await planStore.limit(.chef)
        guard let left = try? await account.remainingToday(kind: "chef", limit: limit) else { return }
        chefRemaining = left
        chefRemainingDay = AIQuota.serverDay(AppClock.now)
    }

    // MARK: Rules

    private func sorted(_ matches: [AIChef.Match]) -> [AIChef.Match] {
        switch sort {
        case .best: matches
        case .quickest: matches.sorted { $0.recipe.minutes < $1.recipe.minutes }
        case .protein: matches.sorted { $0.recipe.nutrition.proteinGrams > $1.recipe.nutrition.proteinGrams }
        }
    }

    private func nextMeal(profile: UserProfile, now: Date) -> MealType {
        let history = store.foodEntries(
            from: calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: calendar.startOfDay(for: now)) ?? now, to: now
        )
        let times = RecipeDiscover.mealTimes(preferences: profile.preferences) { history.usualTime(for: $0, calendar: calendar) }
        return RecipeDiscover.nextMeal(now: now, times: times, calendar: calendar).meal
    }

    /// Discover and My recipes, once each: the user's own version wins over a
    /// Discover recipe with the same name.
    static func withoutCopies(_ discover: [Recipe], own: [Recipe]) -> [Recipe] {
        let names = Set(own.map { FoodSearch.normalized($0.name) })
        return own + discover.filter { !names.contains(FoodSearch.normalized($0.name)) }
    }

    /// What's left of today's protein and energy targets.
    static func remaining(profile: UserProfile, entries: [FoodLogEntry]) -> AIChef.Remaining {
        let eaten = entries.totalNutrition
        return AIChef.Remaining(
            proteinGrams: max(profile.nutritionTargets.proteinGrams - eaten.proteinGrams, 0),
            calories: max(profile.nutritionTargets.calories - eaten.calories, 0)
        )
    }
}

/// "ADD MISSING TO GROCERY", once.
private struct ChefGroceryLink: View {
    let missing: [Recipe.Ingredient]

    @Environment(LocalStore.self) private var store
    @State private var added = false
    @State private var showError = false

    var body: some View {
        Button {
            do {
                try RecipeGrocery.add(missing, servingsScale: 1, store: store)
                added = true
            } catch {
                showError = true
            }
        } label: {
            Text(added ? "On your grocery list" : "Add missing to grocery")
                .vessTextStyle(.labelCapsLink)
                .foregroundStyle(added ? VESSColor.secondaryText : VESSColor.accent)
                .frame(minHeight: VESSHitTarget.minimum, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .vessErrorAlert(isPresented: $showError)
        .accessibilityIdentifier("chef.addMissing")
    }
}
