import Foundation

/// A recipe: one of the bundled Discover recipes, the user's own, or an AI
/// draft the user saved. Nutrition is per serving and always calculated on
/// the device from the ingredients, never taken from the AI.
nonisolated struct Recipe: Identifiable, Hashable, Codable, Sendable {
    nonisolated enum Origin: String, Codable, Sendable {
        /// Bundled with the app (`recipes.json`).
        case discover
        /// Made by the user (R03).
        case user
        /// An AI Chef draft the user checked and saved (R07).
        case ai
    }

    /// Diet tags as in the data: V vegetarian, VG vegan, P pescatarian,
    /// O omnivore, GF gluten-free, DF dairy-free.
    nonisolated enum DietTag: String, Codable, CaseIterable, Sendable {
        case vegetarian = "V"
        case vegan = "VG"
        case pescatarian = "P"
        case omnivore = "O"
        case glutenFree = "GF"
        case dairyFree = "DF"
    }

    /// What a recipe contains, for diet, halal and kosher checks.
    nonisolated enum Content: String, Codable, CaseIterable, Sendable {
        case meat, poultry, pork, fish, shellfish, molluscs, dairy, egg, alcohol
    }

    /// The diets a recipe suits, for plan suggestions.
    nonisolated enum Diet: String, Hashable, Sendable {
        case pescatarian, vegetarian, vegan
    }

    /// Units as written in a recipe ("2 cloves", "1 tbsp").
    nonisolated enum Unit: String, Codable, CaseIterable, Sendable {
        case gram = "g"
        case milliliter = "ml"
        case piece
        case slice
        case tablespoon = "tbsp"
        case teaspoon = "tsp"
        case clove
        case pinch

        /// The matching unit for plans, grocery and the log; `nil` for
        /// cloves and pinches.
        var quantityUnit: QuantityUnit? {
            switch self {
            case .gram: .gram
            case .milliliter: .milliliter
            case .piece: .piece
            case .slice: .slice
            case .tablespoon: .tablespoon
            case .teaspoon: .teaspoon
            case .clove, .pinch: nil
            }
        }
    }

    nonisolated struct Ingredient: Hashable, Codable, Sendable {
        /// Where an ingredient's nutrition comes from.
        nonisolated enum Source: Hashable, Codable, Sendable {
            /// USDA SR Legacy, by NDB number.
            case usda(ndb: String)
            /// An Open Food Facts product, by barcode.
            case openFoodFacts(barcode: String)
            /// Typical label values (`per100`), with a short note.
            case label(String)
            /// Typed in by the user (`per100`).
            case user
        }

        var name: String
        /// The pantry name it matches ("baby spinach").
        var key: String?
        /// Amount for the recipe's servings; `nil` is "to taste".
        var quantity: Double?
        var unit: Unit?
        /// Weight in grams, for nutrition.
        var grams: Double?
        var allergens: Set<Allergen>
        var source: Source?
        /// Per 100 g, for label, user and Open Food Facts ingredients. USDA
        /// ingredients are looked up by `ndb`.
        var per100: NutritionFacts?
        /// "Top with spring onions if you have them."
        var isOptional: Bool

        init(name: String, key: String? = nil, quantity: Double? = nil, unit: Unit? = nil, grams: Double? = nil,
             allergens: Set<Allergen> = [], source: Source? = nil, per100: NutritionFacts? = nil, isOptional: Bool = false) {
            self.name = name
            self.key = key
            self.quantity = quantity
            self.unit = unit
            self.grams = grams
            self.allergens = allergens
            self.source = source
            self.per100 = per100
            self.isOptional = isOptional
        }
    }

    let id: String
    var name: String
    var category: RecipeCategory
    /// Hands-on and cooking time.
    var minutes: Int
    /// Waiting on top, such as "overnight" or "2 h".
    var extraTime: String?
    var servings: Int
    /// Per serving. Values not known for every ingredient are unreported.
    var nutrition: NutritionFacts
    var ingredients: [Ingredient]
    var steps: [String]
    var tip: String?
    var dietTags: Set<DietTag>
    /// Other tags, such as "mediterranean".
    var tags: Set<String>
    var highProtein: Bool
    var contains: Set<Content>
    var allergens: Set<Allergen>
    /// Asset name of the bundled photo; user and AI recipes keep their own
    /// photo with the record instead.
    var photo: String?
    var origin: Origin
    /// When the user saved it; `nil` for Discover recipes.
    var createdAt: Date?

    /// The slot it is planned or logged in by default.
    var mealType: MealType { category.defaultMeal }

    /// Vegan with the VG tag; vegetarian with V or VG; pescatarian without
    /// meat, poultry or pork.
    var diets: Set<Diet> {
        var diets = Set<Diet>()
        if dietTags.contains(.vegan) { diets.insert(.vegan) }
        if !dietTags.isDisjoint(with: [.vegan, .vegetarian]) { diets.insert(.vegetarian) }
        if contains.isDisjoint(with: [.meat, .poultry, .pork]) { diets.insert(.pescatarian) }
        return diets
    }
}

/// The meal-type chips on Discover and the editor.
nonisolated enum RecipeCategory: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack, smoothie, dessert

    /// Smoothies and desserts plan and log as a snack by default; the user
    /// can pick another slot.
    var defaultMeal: MealType {
        switch self {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        case .snack, .smoothie, .dessert: .snack
        }
    }
}
