import Foundation
import Observation
import OSLog

/// The bundled Discover recipes (`recipes.json`, 122 recipes with USDA
/// nutrition). Read once, off the main thread, and kept in memory. USDA
/// ingredients get their per-100 g values from the generic foods, so a
/// skipped ingredient's nutrition can be taken out (`Recipe.without(_:)`).
@Observable
final class RecipeCatalog {
    private(set) var recipes: [Recipe] = []
    private(set) var isLoaded = false

    init(recipes: [Recipe]? = nil) {
        if let recipes {
            self.recipes = recipes
            isLoaded = true
        }
    }

    /// Reads the bundled file in the background, after the generic foods;
    /// later calls do nothing.
    func load(foods: GenericFoodDatabase) async {
        guard !isLoaded else { return }
        await foods.load()
        let table = foods.table
        do {
            recipes = try await Task.detached(priority: .utility) { try Self.bundled(per100: table) }.value
        } catch {
            Logger(subsystem: AppLog.subsystem, category: "Recipes").fault("Reading recipes.json failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoaded = true
    }

    func recipe(id: String) -> Recipe? {
        recipes.first { $0.id == id }
    }

    /// Reads and decodes the bundled file on the calling thread.
    nonisolated static func bundled(per100 table: [String: GenericFood] = [:]) throws -> [Recipe] {
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url), per100: table)
    }

    nonisolated static func decode(_ data: Data, per100 table: [String: GenericFood] = [:]) throws -> [Recipe] {
        try JSONDecoder().decode([Entry].self, from: data).map { entry in
            var recipe = entry.recipe
            for index in recipe.ingredients.indices where recipe.ingredients[index].per100 == nil {
                if case .usda(let ndb) = recipe.ingredients[index].source {
                    recipe.ingredients[index].per100 = table[ndb]?.per100g
                }
            }
            return recipe
        }
    }
}

// MARK: - File format

/// `recipes.json` as written by the data export. Kept apart from `Recipe`,
/// whose stored form belongs to the app.
private nonisolated struct Entry: Decodable {
    struct Nutrition: Decodable {
        let calories: Double
        let proteinGrams: Double
        let carbohydrateGrams: Double
        let fatGrams: Double
        let fiberGrams: Double?
        let sugarGrams: Double?
        let sodiumMilligrams: Double?
        let saturatedFatGrams: Double?

        var facts: NutritionFacts {
            var facts = NutritionFacts(
                calories: calories, proteinGrams: proteinGrams, carbohydrateGrams: carbohydrateGrams, fatGrams: fatGrams,
                fiberGrams: fiberGrams, sugarGrams: sugarGrams, sodiumMilligrams: sodiumMilligrams
            )
            if let saturatedFatGrams { facts.additional[.saturatedFat] = saturatedFatGrams }
            return facts
        }
    }

    /// Label values per 100 g.
    struct Per100: Decodable {
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double?
        let sugar: Double?
        let sodium_mg: Double?
        let satfat: Double?

        var facts: NutritionFacts {
            var facts = NutritionFacts(
                calories: kcal, proteinGrams: protein, carbohydrateGrams: carbs, fatGrams: fat,
                fiberGrams: fiber, sugarGrams: sugar, sodiumMilligrams: sodium_mg
            )
            if let satfat { facts.additional[.saturatedFat] = satfat }
            return facts
        }
    }

    struct Source: Decodable {
        let db: String
        let ndb: String?
        let description: String?
    }

    struct Ingredient: Decodable {
        let name: String
        let key: String?
        let amount: Double?
        let unit: Recipe.Unit?
        let grams: Double?
        let ndb: String?
        let per100: Per100?
        let allergens: Set<Allergen>
        let source: Source
        let optional: Bool?

        var ingredient: Recipe.Ingredient {
            let source: Recipe.Ingredient.Source? = if let ndb { .usda(ndb: ndb) } else { .label(self.source.description ?? self.source.db) }
            return Recipe.Ingredient(
                name: name, key: key, quantity: amount, unit: unit, grams: grams,
                allergens: allergens, source: source, per100: per100?.facts, isOptional: optional ?? false
            )
        }
    }

    let id: String
    let name: String
    let category: RecipeCategory
    let minutes: Int
    let extraTime: String?
    let servings: Int
    let diet: Set<Recipe.DietTag>
    let allergens: Set<Allergen>
    let ingredients: [Ingredient]
    let steps: [String]
    let tip: String?
    let tags: Set<String>?
    let highProtein: Bool
    let contains: Set<Recipe.Content>
    let photo: String?
    let nutritionPerServing: Nutrition

    var recipe: Recipe {
        Recipe(
            id: id, name: name, category: category, minutes: minutes, extraTime: extraTime, servings: servings,
            nutrition: nutritionPerServing.facts, ingredients: ingredients.map(\.ingredient), steps: steps, tip: tip,
            dietTags: diet, tags: tags ?? [], highProtein: highProtein, contains: contains, allergens: allergens,
            photo: photo, origin: .discover, createdAt: nil
        )
    }
}
