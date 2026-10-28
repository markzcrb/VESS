import Foundation

/// `200 { title, dishes, note, remaining }` from the menu function (M02).
nonisolated struct MenuScanResponse: Decodable, Equatable, Sendable {
    struct Dish: Decodable, Equatable, Sendable {
        let name: String
        let section: String?
        let menuText: String?
        let portionG: Double
        let kcal: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let ingredients: [String]
        /// EU-14 names, as `Allergen` raw values.
        let allergens: [String]
        /// meat, pork, poultry, fish, shellfish, molluscs, egg, dairy, alcohol.
        let contains: [String]
        let confidence: String

        enum CodingKeys: String, CodingKey {
            case name, section, kcal, ingredients, allergens, contains, confidence
            case menuText = "menu_text"
            case portionG = "portion_g"
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
        }
    }

    let title: String?
    let dishes: [Dish]
    let note: String?
    let remaining: Int?
}

/// The menu request: the prepared JPEG and the language.
nonisolated struct MenuScanRequest: Encodable, Sendable {
    let imageBase64: String
    let mediaType = "image/jpeg"
    let locale: String

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case mediaType = "media_type"
        case locale
    }

    init(jpeg: Data, locale: String) {
        imageBase64 = jpeg.base64EncodedString()
        self.locale = locale
    }
}

/// M03 portion: Smaller ×0.75, Regular, Larger ×1.25.
nonisolated enum MenuPortion: String, CaseIterable, Sendable {
    case smaller, regular, larger

    var factor: Double {
        switch self {
        case .smaller: 0.75
        case .regular: 1
        case .larger: 1.25
        }
    }
}

/// One dish read from the menu, with its typical-portion estimate.
nonisolated struct MenuDish: Identifiable, Equatable, Sendable {
    /// Its place on the menu.
    let id: Int
    let name: String
    let section: String?
    let menuText: String?
    let portionGrams: Double
    /// For the regular portion.
    let nutrition: NutritionFacts
    let ingredients: [String]
    let allergens: Set<Allergen>
    let contains: Set<Recipe.Content>
    let confidence: EstimatedItem.Confidence

    init(id: Int, _ dish: MenuScanResponse.Dish) {
        self.id = id
        name = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
        section = dish.section?.isEmpty == false ? dish.section : nil
        menuText = dish.menuText?.isEmpty == false ? dish.menuText : nil
        portionGrams = max(dish.portionG, 0)
        nutrition = NutritionFacts(calories: max(dish.kcal, 0), proteinGrams: max(dish.proteinG, 0),
                                   carbohydrateGrams: max(dish.carbsG, 0), fatGrams: max(dish.fatG, 0))
        ingredients = dish.ingredients
        allergens = Set(dish.allergens.compactMap(Allergen.init(rawValue:)))
        contains = Set(dish.contains.compactMap(Recipe.Content.init(rawValue:)))
        confidence = EstimatedItem.Confidence(rawValue: dish.confidence) ?? .low
    }

    func nutrition(_ portion: MenuPortion) -> NutritionFacts {
        nutrition.scaled(by: portion.factor)
    }

    /// Name, menu line and ingredients, for keyword hints.
    var searchText: String {
        ([name, menuText ?? ""] + ingredients).joined(separator: " · ")
    }
}

/// "Often has walnuts": an allergen a dish of this kind usually holds,
/// though the estimate didn't list it.
nonisolated struct MenuHint: Hashable, Sendable {
    let allergen: Allergen
    /// "walnuts", lowercased, for "Ask: often has walnuts".
    let word: String
}

/// Whether a dish fits the user, decided on the device.
nonisolated struct MenuFit: Equatable, Sendable {
    /// The user's allergens the estimate lists: doesn't fit.
    let allergens: Set<Allergen>
    /// Diet, halal, kosher and don't-eat failures (`RecipeFit`).
    let reasons: [RecipeFit.Reason]
    /// The user's allergens a dish like this often has: "Ask" (maybe).
    let hints: [MenuHint]

    var fits: Bool { allergens.isEmpty && reasons.isEmpty }
}

/// The menu scan (M02, M03). Pure and deterministic.
///
/// - Fit: a confirmed allergen of the user's, or the diet (with halal and
///   kosher) read from `contains`, or a don't-eat item in the name or the
///   ingredients, means it doesn't fit. Those dishes are never hidden:
///   they're listed under "Doesn't fit you". A dish that often has one of
///   the user's allergens without it being listed fits, tagged "Ask".
/// - "Best for you": fitting dishes, low confidence last, then those within
///   the energy left before those above it, then closest to the protein left.
nonisolated enum MenuRules {
    /// Lighter: at most this share of the daily energy target per regular portion.
    static let lighterShare = 0.30
    /// Low protein: under this much per regular portion.
    static let lowProteinGrams: Double = 15

    enum Filter: Hashable, Sendable { case best, highProtein, lighter, all }

    static func dishes(from response: MenuScanResponse) -> [MenuDish] {
        response.dishes.enumerated()
            .map { MenuDish(id: $0.offset, $0.element) }
            .filter { !$0.name.isEmpty }
    }

    /// The dish as a recipe, so the one fit rule applies. Diet tags follow
    /// from `contains`; the name is checked as an ingredient too, last, so
    /// a real ingredient names the reason first.
    static func recipe(for dish: MenuDish) -> Recipe {
        var tags = Set<Recipe.DietTag>()
        if dish.contains.isDisjoint(with: [.meat, .poultry, .pork, .fish, .shellfish, .molluscs]) {
            tags.insert(.vegetarian)
            if dish.contains.isDisjoint(with: [.dairy, .egg]) { tags.insert(.vegan) }
        }
        return Recipe(
            id: "menu-\(dish.id)", name: dish.name, category: .dinner, minutes: 0, extraTime: nil, servings: 1,
            nutrition: dish.nutrition,
            ingredients: (dish.ingredients + [dish.name]).map { Recipe.Ingredient(name: $0) },
            steps: [], tip: nil, dietTags: tags, tags: [], highProtein: RecipeNutritionCalculator.isHighProtein(dish.nutrition),
            contains: dish.contains, allergens: dish.allergens, photo: nil, origin: .ai, createdAt: nil
        )
    }

    static func fit(_ dish: MenuDish, preferences: NutritionPreferences, allergies: Set<Allergen>) -> MenuFit {
        let recipeFit = RecipeFit.check(recipe(for: dish), preferences: preferences, allergies: allergies)
        let confirmed = dish.allergens.intersection(allergies)
        return MenuFit(allergens: confirmed, reasons: recipeFit.reasons,
                       hints: hints(for: dish, allergies: allergies.subtracting(confirmed)))
    }

    /// Keyword hints for the user's allergens the estimate didn't list.
    static func hints(for dish: MenuDish, allergies: Set<Allergen>) -> [MenuHint] {
        let text = dish.searchText
        var seen = Set<Allergen>()
        return hintWords.compactMap { keyword, hint in
            guard allergies.contains(hint.allergen), !seen.contains(hint.allergen),
                  IngredientMatcher.contains(keyword, in: text) else { return nil }
            seen.insert(hint.allergen)
            return hint
        }
    }

    /// Dishes that usually hold an allergen without it being in their name.
    static let hintWords: [(keyword: String, hint: MenuHint)] = [
        ("beet salad", MenuHint(allergen: .nuts, word: "walnuts")),
        ("beetroot salad", MenuHint(allergen: .nuts, word: "walnuts")),
        ("waldorf", MenuHint(allergen: .nuts, word: "walnuts")),
        ("goat cheese salad", MenuHint(allergen: .nuts, word: "walnuts")),
        ("carrot cake", MenuHint(allergen: .nuts, word: "walnuts")),
        ("brownie", MenuHint(allergen: .nuts, word: "walnuts")),
        ("muhammara", MenuHint(allergen: .nuts, word: "walnuts")),
        ("pesto", MenuHint(allergen: .nuts, word: "pine nuts or cashews")),
        ("romesco", MenuHint(allergen: .nuts, word: "almonds")),
        ("frangipane", MenuHint(allergen: .nuts, word: "almonds")),
        ("marzipan", MenuHint(allergen: .nuts, word: "almonds")),
        ("biscotti", MenuHint(allergen: .nuts, word: "almonds")),
        ("macaron", MenuHint(allergen: .nuts, word: "almonds")),
        ("nougat", MenuHint(allergen: .nuts, word: "almonds")),
        ("praline", MenuHint(allergen: .nuts, word: "hazelnuts")),
        ("dukkah", MenuHint(allergen: .nuts, word: "hazelnuts")),
        ("baklava", MenuHint(allergen: .nuts, word: "pistachios")),
        ("korma", MenuHint(allergen: .nuts, word: "cashews")),
        ("granola", MenuHint(allergen: .nuts, word: "nuts")),
        ("satay", MenuHint(allergen: .peanuts, word: "peanuts")),
        ("pad thai", MenuHint(allergen: .peanuts, word: "peanuts")),
        ("kung pao", MenuHint(allergen: .peanuts, word: "peanuts")),
        ("gado gado", MenuHint(allergen: .peanuts, word: "peanuts")),
        ("massaman", MenuHint(allergen: .peanuts, word: "peanuts")),
        ("hummus", MenuHint(allergen: .sesame, word: "tahini")),
        ("falafel", MenuHint(allergen: .sesame, word: "sesame")),
        ("sushi", MenuHint(allergen: .sesame, word: "sesame")),
        ("caesar", MenuHint(allergen: .fish, word: "anchovies")),
        ("puttanesca", MenuHint(allergen: .fish, word: "anchovies")),
        ("niçoise", MenuHint(allergen: .fish, word: "anchovies")),
        ("nicoise", MenuHint(allergen: .fish, word: "anchovies")),
        ("paella", MenuHint(allergen: .crustaceans, word: "prawns")),
        ("bisque", MenuHint(allergen: .crustaceans, word: "shellfish")),
        ("aioli", MenuHint(allergen: .eggs, word: "egg")),
        ("mayonnaise", MenuHint(allergen: .eggs, word: "egg")),
        ("carbonara", MenuHint(allergen: .eggs, word: "egg")),
        ("hollandaise", MenuHint(allergen: .eggs, word: "egg")),
        ("tiramisu", MenuHint(allergen: .eggs, word: "egg")),
        ("risotto", MenuHint(allergen: .milk, word: "butter and parmesan")),
        ("gratin", MenuHint(allergen: .milk, word: "cream and cheese")),
        ("tempura", MenuHint(allergen: .gluten, word: "wheat batter")),
        ("schnitzel", MenuHint(allergen: .gluten, word: "breadcrumbs")),
        ("katsu", MenuHint(allergen: .gluten, word: "breadcrumbs")),
        ("vinaigrette", MenuHint(allergen: .mustard, word: "mustard")),
        ("remoulade", MenuHint(allergen: .mustard, word: "mustard")),
        ("teriyaki", MenuHint(allergen: .soy, word: "soy sauce")),
        ("bolognese", MenuHint(allergen: .celery, word: "celery")),
    ]

    /// One dish as listed, with its fit and whether it was chosen.
    struct Row: Identifiable, Equatable, Sendable {
        let dish: MenuDish
        let fit: MenuFit
        var id: Int { dish.id }
    }

    static func rows(_ dishes: [MenuDish], preferences: NutritionPreferences, allergies: Set<Allergen>) -> [Row] {
        dishes.map { Row(dish: $0, fit: fit($0, preferences: preferences, allergies: allergies)) }
    }

    /// Fitting dishes for a chip, in its order; `.all` is every dish in menu
    /// order (the ones that don't fit too, greyed).
    static func list(_ rows: [Row], filter: Filter, caloriesLeft: Double, proteinLeft: Double, energyTarget: Double) -> [Row] {
        let fitting = rows.filter(\.fit.fits)
        switch filter {
        case .best:
            return fitting.sorted { a, b in
                let lowA = a.dish.confidence == .low, lowB = b.dish.confidence == .low
                if lowA != lowB { return !lowA }
                let overA = a.dish.nutrition.calories > caloriesLeft, overB = b.dish.nutrition.calories > caloriesLeft
                if overA != overB { return !overA }
                let gapA = abs(a.dish.nutrition.proteinGrams - proteinLeft), gapB = abs(b.dish.nutrition.proteinGrams - proteinLeft)
                if gapA != gapB { return gapA < gapB }
                return a.id < b.id
            }
        case .highProtein:
            return fitting.filter { RecipeNutritionCalculator.isHighProtein($0.dish.nutrition) }
                .sorted { ($0.dish.nutrition.proteinGrams, -$0.id) > ($1.dish.nutrition.proteinGrams, -$1.id) }
        case .lighter:
            return fitting.filter { $0.dish.nutrition.calories <= energyTarget * lighterShare }
                .sorted { ($0.dish.nutrition.calories, $0.id) < ($1.dish.nutrition.calories, $1.id) }
        case .all:
            return rows
        }
    }

    /// The fitting dish with the most protein within the energy left: "Best protein".
    static func bestProtein(_ rows: [Row], caloriesLeft: Double) -> Int? {
        rows.filter { $0.fit.fits && $0.fit.hints.isEmpty && $0.dish.nutrition.calories <= caloriesLeft }
            .max { ($0.dish.nutrition.proteinGrams, -$0.id) < ($1.dish.nutrition.proteinGrams, -$1.id) }?.id
    }

    /// The entries Add logs, one per dish, estimated from a photo and named
    /// after the menu.
    static func entries(_ chosen: [(dish: MenuDish, portion: MenuPortion)], menuName: String?, userID: UUID,
                        meal: MealType, at date: Date) -> [FoodLogEntry] {
        chosen.map { dish, portion in
            var entry = FoodLogEntry(
                id: UUID(), userID: userID, foodID: nil, foodName: dish.name, mealType: meal,
                quantity: (dish.portionGrams > 0 ? dish.portionGrams : 100) * portion.factor, servingUnit: .gram,
                nutrition: dish.nutrition(portion), loggedAt: date, source: .photoEstimate
            )
            entry.menuName = menuName
            return entry
        }
    }
}
