import Foundation

/// AI Chef (R05): which Discover and My recipes to cook from what's at home.
/// Pure and deterministic; no AI is involved in the ranking.
nonisolated enum AIChef {
    /// How a recipe sits against the pantry.
    nonisolated struct PantryUse: Equatable, Sendable {
        /// Ingredients at home, with the pantry item that covers each.
        let have: [(ingredient: Recipe.Ingredient, item: InventoryItem)]
        /// Needed and not at home.
        let missing: [Recipe.Ingredient]
        /// Optional and not at home ("Missing · optional").
        let missingOptional: [Recipe.Ingredient]
        /// Use-soon pantry items the recipe uses, each once.
        let useSoon: [InventoryItem]

        /// "6 of 8 at home": salt, pepper, water and optional items don't
        /// count either way.
        var atHomeCount: Int { have.filter { !$0.ingredient.isOptional }.count }
        var countedTotal: Int { atHomeCount + missing.count }
        var shareAtHome: Double { countedTotal == 0 ? 0 : Double(atHomeCount) / Double(countedTotal) }

        static func == (lhs: PantryUse, rhs: PantryUse) -> Bool {
            lhs.have.map(\.ingredient) == rhs.have.map(\.ingredient) && lhs.have.map(\.item.id) == rhs.have.map(\.item.id)
                && lhs.missing == rhs.missing && lhs.missingOptional == rhs.missingOptional && lhs.useSoon.map(\.id) == rhs.useSoon.map(\.id)
        }
    }

    /// "Swap cod for tofu": a missing ingredient and what's at home instead.
    nonisolated struct Swap: Equatable, Sendable {
        let missing: Recipe.Ingredient
        let replacement: String
        let item: InventoryItem

        static func == (lhs: Swap, rhs: Swap) -> Bool {
            lhs.missing == rhs.missing && lhs.replacement == rhs.replacement && lhs.item.id == rhs.item.id
        }
    }

    nonisolated struct Match: Identifiable, Equatable, Sendable {
        let recipe: Recipe
        let pantry: PantryUse
        let swaps: [Swap]
        var id: String { recipe.id }
    }

    nonisolated struct Filters: Equatable, Sendable {
        var meal: MealType?
        var under30Minutes = false
        var highProtein = false
        var usesUseSoon = false

        static let quickMinutes = 30
    }

    /// What's left of today's targets, for the third ranking step.
    nonisolated struct Remaining: Equatable, Sendable {
        let proteinGrams: Double
        let calories: Double
    }

    /// Never counted as at home or missing.
    static let staples: Set<String> = ["salt", "sea salt", "pepper", "black pepper", "white pepper", "water", "cold water", "hot water", "boiling water"]

    static func isStaple(_ ingredient: Recipe.Ingredient) -> Bool {
        [ingredient.key, ingredient.name].compactMap(\.self).contains { staples.contains(FoodSearch.normalized($0)) }
    }

    /// At home: available and not past its date. Use soon: today, tomorrow
    /// or within the 3-day threshold.
    static func pantryUse(_ recipe: Recipe, pantry: [InventoryItem], now: Date, calendar: Calendar) -> PantryUse {
        let usable = pantry.filter { item in
            guard item.status == .available else { return false }
            if case .expired = item.expirationStatus(now: now, calendar: calendar) { return false }
            return true
        }
        var have: [(ingredient: Recipe.Ingredient, item: InventoryItem)] = []
        var missing: [Recipe.Ingredient] = []
        var missingOptional: [Recipe.Ingredient] = []
        for ingredient in recipe.ingredients where !isStaple(ingredient) {
            // The longest pantry name wins ("Baby spinach" over "Spinach").
            if let item = usable.filter({ IngredientMatcher.pantryName($0.name, matches: ingredient) }).max(by: { $0.name.count < $1.name.count }) {
                have.append((ingredient, item))
            } else if ingredient.isOptional {
                missingOptional.append(ingredient)
            } else {
                missing.append(ingredient)
            }
        }
        var seen = Set<UUID>()
        let useSoon = have.map(\.item).filter { item in
            item.expirationStatus(now: now, calendar: calendar).needsAttention && seen.insert(item.id).inserted
        }
        return PantryUse(have: have, missing: missing, missingOptional: missingOptional, useSoon: useSoon)
    }

    /// Best matches first. Candidates are the recipes that fit (`RecipeFit`);
    /// ingredients the user doesn't eat are never used, even with "Show
    /// recipes that don't fit" on. Ranked by, in order:
    /// 1. use-soon items used, most first;
    /// 2. share of ingredients at home;
    /// 3. today's remaining targets: recipes within the remaining energy
    ///    first, closest to the remaining protein; then the rest, least over.
    static func rank(
        _ recipes: [Recipe],
        preferences: NutritionPreferences,
        allergies: Set<Allergen>,
        pantry: [InventoryItem],
        remaining: Remaining,
        filters: Filters = Filters(),
        now: Date,
        calendar: Calendar
    ) -> [Match] {
        let matches = recipes.compactMap { original -> Match? in
            let fit = RecipeFit.check(original, preferences: preferences, allergies: allergies)
            guard fit.fits else { return nil }
            // Skipped optional ingredients are neither at home nor missing.
            let recipe = original.without(fit.skipped)
            if let meal = filters.meal, recipe.mealType != meal { return nil }
            if filters.under30Minutes, recipe.minutes > Filters.quickMinutes || recipe.extraTime != nil { return nil }
            if filters.highProtein, !recipe.highProtein { return nil }
            let use = pantryUse(recipe, pantry: pantry, now: now, calendar: calendar)
            if filters.usesUseSoon, use.useSoon.isEmpty { return nil }
            return Match(
                recipe: recipe, pantry: use,
                swaps: swaps(for: recipe, use: use, pantry: pantry, preferences: preferences, allergies: allergies, now: now, calendar: calendar)
            )
        }
        return matches.sorted { lhs, rhs in
            if lhs.pantry.useSoon.count != rhs.pantry.useSoon.count { return lhs.pantry.useSoon.count > rhs.pantry.useSoon.count }
            if lhs.pantry.shareAtHome != rhs.pantry.shareAtHome { return lhs.pantry.shareAtHome > rhs.pantry.shareAtHome }
            let (l, r) = (targetFit(lhs.recipe.nutrition, remaining), targetFit(rhs.recipe.nutrition, remaining))
            if l != r { return l.lexicographicallyPrecedes(r) }
            return lhs.recipe.name.localizedStandardCompare(rhs.recipe.name) == .orderedAscending
        }
    }

    /// `[0, distance to remaining protein]` within the remaining energy,
    /// `[1, kcal over]` above it. Smaller is better.
    static func targetFit(_ nutrition: NutritionFacts, _ remaining: Remaining) -> [Double] {
        nutrition.calories <= remaining.calories
            ? [0, abs(nutrition.proteinGrams - remaining.proteinGrams)]
            : [1, nutrition.calories - remaining.calories]
    }

    // MARK: Swaps

    /// One food that can stand in for another, with what it brings.
    nonisolated struct SwapFood: Sendable {
        let name: String
        let contents: Set<Recipe.Content>
        let allergens: Set<Allergen>
    }

    /// The only swaps AI Chef offers: cod ↔ salmon ↔ tofu, chicken breast ↔
    /// turkey breast ↔ tofu, Greek yogurt ↔ skyr, milk ↔ soy drink.
    static let swapGroups: [[SwapFood]] = {
        let cod = SwapFood(name: "cod", contents: [.fish], allergens: [.fish])
        let salmon = SwapFood(name: "salmon", contents: [.fish], allergens: [.fish])
        let tofu = SwapFood(name: "tofu", contents: [], allergens: [.soy])
        let chicken = SwapFood(name: "chicken breast", contents: [.poultry], allergens: [])
        let turkey = SwapFood(name: "turkey breast", contents: [.poultry], allergens: [])
        let yogurt = SwapFood(name: "greek yogurt", contents: [.dairy], allergens: [.milk])
        let skyr = SwapFood(name: "skyr", contents: [.dairy], allergens: [.milk])
        let milk = SwapFood(name: "milk", contents: [.dairy], allergens: [.milk])
        let soyDrink = SwapFood(name: "soy drink", contents: [], allergens: [.soy])
        return [[cod, salmon, tofu], [chicken, turkey, tofu], [yogurt, skyr], [milk, soyDrink]]
    }()

    /// Swaps for missing ingredients: only from `swapGroups`, only when the
    /// stand-in is at home, and only when the swapped recipe still fits.
    static func swaps(
        for recipe: Recipe, use: PantryUse, pantry: [InventoryItem],
        preferences: NutritionPreferences, allergies: Set<Allergen>, now: Date, calendar: Calendar
    ) -> [Swap] {
        let usable = pantry.filter { item in
            guard item.status == .available else { return false }
            if case .expired = item.expirationStatus(now: now, calendar: calendar) { return false }
            return true
        }
        return use.missing.compactMap { missing in
            guard !ContentKeywords.exceptions.contains(where: { IngredientMatcher.contains($0, in: missing.name) }) else { return nil }
            for group in swapGroups {
                guard let from = group.first(where: { IngredientMatcher.ingredient(missing, contains: $0.name) }) else { continue }
                for to in group where to.name != from.name {
                    guard let item = usable.first(where: { IngredientMatcher.contains(to.name, in: $0.name) }) else { continue }
                    let swapped = swapping(missing, from: from, to: to, in: recipe)
                    if RecipeFit.check(swapped, preferences: preferences, allergies: allergies).fits {
                        return Swap(missing: missing, replacement: to.name, item: item)
                    }
                }
            }
            return nil
        }
    }

    /// The recipe with `ingredient` replaced: allergens from the ingredients
    /// again; contents lose what only that ingredient brought.
    static func swapping(_ ingredient: Recipe.Ingredient, from: SwapFood, to: SwapFood, in recipe: Recipe) -> Recipe {
        var swapped = recipe
        guard let index = recipe.ingredients.firstIndex(of: ingredient) else { return recipe }
        var replacement = ingredient
        replacement.name = to.name.prefix(1).uppercased() + to.name.dropFirst()
        replacement.key = to.name
        replacement.allergens = to.allergens
        replacement.source = nil
        swapped.ingredients[index] = replacement
        swapped.allergens = swapped.ingredients.reduce(into: Set<Allergen>()) { $0.formUnion($1.allergens) }
        for content in from.contents where !to.contents.contains(content) {
            let others = swapped.ingredients.enumerated().contains { $0.offset != index && ContentKeywords.matches($0.element.name, content) }
            if !others { swapped.contains.remove(content) }
        }
        swapped.contains.formUnion(to.contents)
        return swapped
    }
}
