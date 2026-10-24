import Foundation

/// What a new AI recipe should aim for (R06).
nonisolated enum ChefGoal: String, CaseIterable, Sendable {
    case highProtein = "high_protein"
    case lighter
    case quick
    case comfort
}

/// `POST /functions/v1/chef`. Only these fields leave the iPhone: the pantry
/// list (names and use-soon), the choices on R06, the diet and avoid list,
/// allergens, today's protein gap and the language. Nothing else from the log.
nonisolated struct ChefRequest: Encodable, Equatable, Sendable {
    nonisolated struct PantryItem: Encodable, Equatable, Sendable {
        let name: String
        let useSoon: Bool

        enum CodingKeys: String, CodingKey {
            case name
            case useSoon = "use_soon"
        }
    }

    let pantry: [PantryItem]
    let mustUse: [String]
    let meal: String
    let goal: String
    let servings: Int
    let onlyWhatIHave: Bool
    let diet: String
    let avoid: [String]
    let allergens: [String]
    let proteinGapGrams: Double?
    let locale: String

    enum CodingKeys: String, CodingKey {
        case pantry
        case mustUse = "must_use"
        case meal, goal, servings
        case onlyWhatIHave = "only_what_i_have"
        case diet, avoid, allergens
        case proteinGapGrams = "protein_gap_g"
        case locale
    }

    /// The server's limits: 80 pantry items, 10 must-use, 1–8 servings.
    static let maxPantry = 80

    static func make(
        pantry: [InventoryItem], mustUse: [InventoryItem], meal: MealType, goal: ChefGoal?, servings: Int,
        onlyWhatIHave: Bool, preferences: NutritionPreferences, allergies: Set<Allergen>,
        proteinGapGrams: Double?, locale: String, now: Date, calendar: Calendar
    ) -> ChefRequest {
        let usable = pantry.filter { item in
            guard item.status == .available else { return false }
            if case .expired = item.expirationStatus(now: now, calendar: calendar) { return false }
            return true
        }
        return ChefRequest(
            pantry: usable.prefix(maxPantry).map { PantryItem(name: $0.name, useSoon: $0.expirationStatus(now: now, calendar: calendar).needsAttention) },
            mustUse: mustUse.prefix(10).map(\.name),
            meal: meal.rawValue,
            goal: goal?.rawValue ?? "none",
            servings: min(max(servings, 1), 8),
            onlyWhatIHave: onlyWhatIHave,
            diet: dietDescription(preferences),
            avoid: preferences.avoidIngredients,
            allergens: Allergen.allCases.filter { allergies.contains($0) }.map(\.rawValue),
            proteinGapGrams: proteinGapGrams.flatMap { $0 > 0 ? ($0 * 10).rounded() / 10 : nil },
            locale: locale
        )
    }

    /// "pescatarian; prefers high-protein, lower-carb", in plain words.
    static func dietDescription(_ preferences: NutritionPreferences) -> String {
        let diet = switch preferences.diet {
        case .noRestrictions: "no restrictions"
        case .pescatarian: "pescatarian"
        case .vegetarian: "vegetarian"
        case .vegan: "vegan"
        case .flexitarian: "flexitarian (mostly vegetarian)"
        }
        let prefers = FoodPreference.allCases.filter { preferences.alsoPrefer.contains($0) }.map { preference in
            switch preference {
            case .highProtein: "high-protein"
            case .lowerCarb: "lower-carb"
            case .mediterranean: "mediterranean"
            case .glutenFree: "gluten-free"
            case .dairyFree: "dairy-free"
            case .halal: "halal"
            case .kosher: "kosher"
            }
        }
        return prefers.isEmpty ? diet : "\(diet); prefers \(prefers.joined(separator: ", "))"
    }
}

/// `200 { recipe, remaining, estimated }` from the chef function.
nonisolated struct ChefResponse: Decodable, Equatable, Sendable {
    nonisolated struct Ingredient: Decodable, Equatable, Sendable {
        let name: String
        let amount: Double
        let unit: String
        let grams: Double
        let fromPantry: Bool?
        let usdaHint: String?

        enum CodingKeys: String, CodingKey {
            case name, amount, unit, grams
            case fromPantry = "from_pantry"
            case usdaHint = "usda_hint"
        }
    }

    nonisolated struct Draft: Decodable, Equatable, Sendable {
        let name: String
        let minutes: Int
        let servings: Int
        let ingredients: [Ingredient]
        let steps: [String]
        let tip: String?
    }

    let recipe: Draft
    let remaining: Int?
}

/// Turns the model's draft into a VESS recipe on the device: every
/// ingredient matched to a USDA food (the pantry item's chosen food first,
/// then the model's USDA hint, then the name), nutrition recalculated,
/// allergens worked out again. The model's own claims are never trusted.
nonisolated enum ChefDraftBuilder {
    nonisolated struct Draft: Equatable, Sendable {
        let recipe: Recipe
        /// Ingredients without nutrition data ("No nutrition data · Choose food").
        let unmatched: [String]
        var isPartial: Bool { !unmatched.isEmpty }
    }

    nonisolated enum Outcome: Equatable, Sendable {
        case draft(Draft)
        /// It used something the user is allergic to, avoids or whose diet
        /// excludes it: not shown ("That draft used something you avoid.").
        case conflict(RecipeFit)
    }

    static func build(
        _ response: ChefResponse, meal: MealType, preferences: NutritionPreferences, allergies: Set<Allergen>,
        pantry: [InventoryItem], search: (String) -> GenericFood?, food: (String) -> GenericFood?
    ) -> Outcome {
        let ingredients = response.recipe.ingredients.map { item -> (Recipe.Ingredient, Bool) in
            let match = matchedFood(for: item, pantry: pantry, search: search, food: food)
            var allergens = RecipeDerivation.allergens(forName: item.name)
            if let hint = item.usdaHint { allergens.formUnion(RecipeDerivation.allergens(forName: hint)) }
            if let match { allergens.formUnion(RecipeDerivation.allergens(forName: match.name)) }
            let unit = Recipe.Unit(rawValue: item.unit) ?? .gram
            let ingredient = Recipe.Ingredient(
                name: item.name, key: item.name.lowercased(), quantity: item.amount > 0 ? item.amount : nil, unit: unit,
                grams: item.grams > 0 ? item.grams : (unit == .gram || unit == .milliliter ? item.amount : nil),
                allergens: allergens, source: match.map { .usda(ndb: $0.id) }, per100: match?.per100g
            )
            return (ingredient, match != nil)
        }
        let category: RecipeCategory = switch meal {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        case .snack: .snack
        }
        let base = Recipe(
            id: "ai-\(UUID().uuidString)", name: response.recipe.name, category: category,
            minutes: response.recipe.minutes, extraTime: nil, servings: max(response.recipe.servings, 1),
            nutrition: .zero, ingredients: ingredients.map(\.0), steps: response.recipe.steps,
            tip: response.recipe.tip, dietTags: [], tags: [], highProtein: false, contains: [], allergens: [],
            photo: nil, origin: .ai, createdAt: nil
        )
        let recipe = RecipeDerivation.complete(base) { _ in nil }.recipe
        // Checked again here: the model can be wrong.
        let fit = RecipeFit.check(recipe, preferences: preferences, allergies: allergies)
        guard fit.fits else { return .conflict(fit) }
        return .draft(Draft(recipe: recipe, unmatched: ingredients.filter { !$0.1 }.map(\.0.name)))
    }

    /// The pantry item's chosen USDA food, else the best match for the
    /// model's USDA hint, else for the name.
    static func matchedFood(
        for item: ChefResponse.Ingredient, pantry: [InventoryItem],
        search: (String) -> GenericFood?, food: (String) -> GenericFood?
    ) -> GenericFood? {
        let plain = Recipe.Ingredient(name: item.name, key: item.name.lowercased())
        if let chosen = pantry.first(where: { $0.genericFoodID != nil && IngredientMatcher.pantryName($0.name, matches: plain) })?.genericFoodID,
           let match = food(chosen) {
            return match
        }
        if let hint = item.usdaHint, !hint.isEmpty, let match = search(hint) { return match }
        return search(item.name)
    }
}

/// The AI daily limits count per UTC day.
nonisolated enum AIQuota {
    /// When today's count starts again: the next 00:00 UTC.
    static func resetTime(after now: Date) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let today = utc.startOfDay(for: now)
        return utc.date(byAdding: .day, value: 1, to: today) ?? now
    }

    /// The server's day for `now`: "2026-10-24".
    static func serverDay(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
