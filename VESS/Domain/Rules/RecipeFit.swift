import Foundation

/// Whether a recipe fits the user: one rule for Discover, AI Chef and Plan
/// suggestions. Pure and deterministic.
///
/// 1. Allergens: a hard filter everywhere, even with "Show recipes that
///    don't fit" on. Such a recipe is never shown.
/// 2. Diet: vegan needs the VG tag; vegetarian V or VG; pescatarian no meat,
///    poultry or pork; flexitarian and no restrictions don't filter. Halal:
///    no pork or alcohol. Kosher: no pork, shellfish or molluscs, and no meat
///    or poultry with dairy. Halal and kosher are read from the ingredients,
///    not from a certification.
/// 3. Ingredients you don't eat: matched against each ingredient's key and
///    name (`IngredientMatcher`). When only optional ingredients match, the
///    recipe still fits and they are skipped ("Without coriander"); an
///    optional ingredient with an allergen still hides the recipe.
/// Diet and don't-eat failures are hidden unless the user shows recipes that
/// don't fit; then they are greyed with the reason.
nonisolated struct RecipeFit: Equatable, Sendable {
    nonisolated enum Reason: Hashable, Sendable {
        /// "Has chicken": what breaks the diet, with the ingredient when it
        /// can be named.
        case has(Recipe.Content, ingredient: String?)
        /// Vegan or vegetarian without the tag, and nothing named.
        case notTagged(Diet)
        /// Kosher: meat or poultry with dairy.
        case meatWithDairy
        /// "Contains mushrooms": a don't-eat item, as the user typed it.
        case avoid(String)
    }

    /// The user's allergens in the recipe. Not empty: never shown.
    let allergens: Set<Allergen>
    let reasons: [Reason]
    /// Don't-eat items found only in optional ingredients, as the user typed
    /// them: those ingredients are left out (`Recipe.without(_:)`).
    var skipped: [String] = []

    var isBlocked: Bool { !allergens.isEmpty }
    var fits: Bool { allergens.isEmpty && reasons.isEmpty }
    /// Fails only on ingredients the user doesn't eat: still opens from
    /// search, tagged "Contains mushrooms".
    var failsOnlyOnAvoid: Bool {
        allergens.isEmpty && !reasons.isEmpty && reasons.allSatisfy { if case .avoid = $0 { true } else { false } }
    }

    /// Listed in Discover lists and collections.
    func isListed(showNonFitting: Bool) -> Bool {
        !isBlocked && (reasons.isEmpty || showNonFitting)
    }

    static func check(_ recipe: Recipe, preferences: NutritionPreferences, allergies: Set<Allergen>) -> RecipeFit {
        var reasons: [Reason] = []
        func has(_ contents: [Recipe.Content]) {
            for content in Recipe.Content.allCases where contents.contains(content) && recipe.contains.contains(content) {
                reasons.append(.has(content, ingredient: ContentKeywords.ingredient(in: recipe, for: content)))
            }
        }

        switch preferences.diet {
        case .vegan:
            if !recipe.dietTags.contains(.vegan) {
                has([.meat, .poultry, .pork, .fish, .shellfish, .molluscs, .dairy, .egg])
                if reasons.isEmpty { reasons.append(.notTagged(.vegan)) }
            }
        case .vegetarian:
            if recipe.dietTags.isDisjoint(with: [.vegetarian, .vegan]) {
                has([.meat, .poultry, .pork, .fish, .shellfish, .molluscs])
                if reasons.isEmpty { reasons.append(.notTagged(.vegetarian)) }
            }
        case .pescatarian:
            has([.meat, .poultry, .pork])
        case .flexitarian, .noRestrictions:
            break
        }
        if preferences.alsoPrefer.contains(.halal) {
            has([.pork, .alcohol])
        }
        if preferences.alsoPrefer.contains(.kosher) {
            has([.pork, .shellfish, .molluscs])
            if !recipe.contains.isDisjoint(with: [.meat, .poultry]) && recipe.contains.contains(.dairy) {
                reasons.append(.meatWithDairy)
            }
        }
        var skipped: [String] = []
        for item in preferences.avoidIngredients {
            let hits = recipe.ingredients.filter { IngredientMatcher.ingredient($0, contains: item) }
            if hits.isEmpty { continue }
            if hits.allSatisfy(\.isOptional) { skipped.append(item) } else { reasons.append(.avoid(item)) }
        }

        var seen = Set<Reason>()
        return RecipeFit(
            allergens: recipe.allergens.intersection(allergies),
            reasons: reasons.filter { seen.insert($0).inserted },
            skipped: skipped
        )
    }

    /// "Also prefer" chips rank recipes up; they never hide one. One point
    /// each: high-protein, lower-carb (≤ 30 g carbs per serving), gluten-free
    /// (GF), dairy-free (DF), Mediterranean; flexitarian puts vegetarian
    /// recipes first.
    static func boost(_ recipe: Recipe, preferences: NutritionPreferences) -> Int {
        var score = 0
        let prefer = preferences.alsoPrefer
        if prefer.contains(.highProtein), recipe.highProtein { score += 1 }
        if prefer.contains(.lowerCarb), recipe.nutrition.isReported(.carbohydrates), recipe.nutrition.carbohydrateGrams <= lowerCarbGrams { score += 1 }
        if prefer.contains(.glutenFree), recipe.dietTags.contains(.glutenFree) { score += 1 }
        if prefer.contains(.dairyFree), recipe.dietTags.contains(.dairyFree) { score += 1 }
        if prefer.contains(.mediterranean), recipe.tags.contains("mediterranean") { score += 1 }
        if preferences.diet == .flexitarian, !recipe.dietTags.isDisjoint(with: [.vegetarian, .vegan]) { score += 1 }
        return score
    }

    /// Lower carb: at most this much per serving.
    static let lowerCarbGrams: Double = 30
}

nonisolated extension Recipe {
    /// The recipe without the optional ingredients that match `skipped`, and
    /// without their nutrition. Allergens stay as they were: an optional
    /// allergen still counts.
    func without(_ skipped: [String]) -> Recipe {
        guard !skipped.isEmpty else { return self }
        let left = ingredients.filter { ingredient in
            !(ingredient.isOptional && skipped.contains { IngredientMatcher.ingredient(ingredient, contains: $0) })
        }
        guard left.count != ingredients.count else { return self }
        var copy = self
        copy.ingredients = left
        let removed = ingredients.filter { !left.contains($0) }
        let servings = Double(Swift.max(self.servings, 1))
        for ingredient in removed {
            guard let per100 = ingredient.per100, let grams = ingredient.grams else { continue }
            let factor = grams / 100 / servings
            copy.nutrition.calories -= per100.calories * factor
            copy.nutrition.proteinGrams -= per100.proteinGrams * factor
            copy.nutrition.carbohydrateGrams -= per100.carbohydrateGrams * factor
            copy.nutrition.fatGrams -= per100.fatGrams * factor
            if let value = per100.fiberGrams { copy.nutrition.fiberGrams = copy.nutrition.fiberGrams.map { $0 - value * factor } }
            if let value = per100.sugarGrams { copy.nutrition.sugarGrams = copy.nutrition.sugarGrams.map { $0 - value * factor } }
            if let value = per100.sodiumMilligrams { copy.nutrition.sodiumMilligrams = copy.nutrition.sodiumMilligrams.map { $0 - value * factor } }
            if let value = per100.additional[.saturatedFat] { copy.nutrition.additional[.saturatedFat] = copy.nutrition.additional[.saturatedFat].map { $0 - value * factor } }
        }
        copy.highProtein = RecipeNutritionCalculator.isHighProtein(copy.nutrition)
        return copy
    }
}

/// Ingredient words for each kind of content, to name what breaks a diet
/// ("Has chicken") and to check a swap.
nonisolated enum ContentKeywords {
    static let words: [Recipe.Content: [String]] = [
        .poultry: ["chicken", "turkey", "duck"],
        .meat: ["beef", "lamb", "veal", "pork", "bacon", "ham", "chorizo", "salami", "prosciutto", "pancetta"],
        .pork: ["pork", "bacon", "ham", "chorizo", "salami", "prosciutto", "pancetta"],
        .fish: ["fish", "cod", "salmon", "tuna", "trout", "mackerel", "sardine", "anchovy", "sea bass", "haddock", "herring", "pollock"],
        .shellfish: ["prawn", "shrimp", "crab", "lobster", "langoustine"],
        .molluscs: ["mussel", "squid", "clam", "oyster", "scallop", "octopus"],
        .dairy: ["milk", "cheese", "yogurt", "yoghurt", "cream", "butter", "feta", "halloumi", "ricotta", "mozzarella", "parmesan", "skyr", "quark", "kefir", "tvaroh"],
        .egg: ["egg"],
        .alcohol: ["wine", "beer", "mirin", "sake", "rum", "brandy", "cider"],
    ]

    /// Words that look like a content word but aren't ("coconut milk",
    /// "peanut butter").
    static let exceptions = [
        "coconut milk", "peanut butter", "cocoa butter", "oat milk", "soy milk", "almond milk", "oat drink", "soy drink",
        "cream of tartar", "soy yogurt", "soy yoghurt", "coconut yogurt", "oat yogurt", "butter lettuce", "butter beans", "cider vinegar",
    ]

    /// Whether an ingredient name holds this kind of content.
    static func matches(_ name: String, _ content: Recipe.Content) -> Bool {
        guard !exceptions.contains(where: { IngredientMatcher.contains($0, in: name) }) else { return false }
        return (words[content] ?? []).contains { IngredientMatcher.contains($0, in: name) }
    }

    /// The first ingredient that holds `content`, lowercased ("chicken
    /// thighs"); `nil` if none can be named.
    static func ingredient(in recipe: Recipe, for content: Recipe.Content) -> String? {
        recipe.ingredients.first { matches($0.name, content) }?.name.lowercased()
    }
}
