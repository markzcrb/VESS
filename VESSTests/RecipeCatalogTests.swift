import Foundation
import SwiftData
import UIKit
import Testing
@testable import VESS

@Suite("Recipes: catalog and storage")
struct RecipeCatalogTests {
    private let calendar = Calendar.current

    @Test("The bundled file has 122 Discover recipes with unique ids, ingredients, steps and a photo each")
    func bundled() throws {
        let recipes = try RecipeCatalog.bundled()
        #expect(recipes.count == 122)
        #expect(Set(recipes.map(\.id)).count == 122)
        for recipe in recipes {
            #expect(recipe.origin == .discover)
            #expect(!recipe.ingredients.isEmpty && !recipe.steps.isEmpty, "\(recipe.id)")
            #expect(recipe.servings >= 1 && recipe.minutes > 0, "\(recipe.id)")
            #expect(recipe.photo == recipe.id, "\(recipe.id)")
            // A recipe's allergens are its ingredients' allergens.
            #expect(recipe.allergens == recipe.ingredients.reduce(into: Set<Allergen>()) { $0.formUnion($1.allergens) }, "\(recipe.id)")
            // Every ingredient has a source: USDA by number or label values.
            for ingredient in recipe.ingredients {
                switch ingredient.source {
                case .usda: break
                case .label: #expect(ingredient.per100 != nil, "\(recipe.id) \(ingredient.name)")
                default: Issue.record("\(recipe.id) \(ingredient.name) has no source")
                }
            }
        }
        #expect(Dictionary(grouping: recipes, by: \.category).mapValues(\.count) == [
            .breakfast: 20, .lunch: 20, .dinner: 22, .snack: 20, .smoothie: 20, .dessert: 20,
        ])
    }

    @Test("Every Discover recipe's photo is in the asset catalog")
    func photos() throws {
        let missing = try RecipeCatalog.bundled().compactMap(\.photo).filter { UIImage(named: $0) == nil }
        #expect(missing.isEmpty, "Missing: \(missing)")
    }

    @Test("Values come through: units, optional items, extra time, tip, tags, saturated fat")
    func fields() throws {
        let recipes = try RecipeCatalog.bundled()
        let oats = try #require(recipes.first { $0.id == "001-overnight-oats-with-berries-and-chia" })
        #expect(oats.extraTime == "overnight")
        #expect(oats.dietTags == [.vegan, .dairyFree])
        #expect(oats.nutrition.calories == 385 && oats.nutrition.sugarGrams == nil)
        #expect(oats.nutrition.additional[.saturatedFat] == 1.2)
        #expect(oats.ingredients[0].source == .usda(ndb: "08120"))
        #expect(oats.ingredients[1].per100?.calories == 46)

        let cod = try #require(recipes.first { $0.id == MockData.tonightRecipeID })
        #expect(cod.category == .dinner && cod.mealType == .dinner && cod.highProtein)
        #expect(cod.contains == [.fish, .alcohol])
        #expect(cod.diets == [.pescatarian])
        #expect(cod.tip != nil)

        #expect(recipes.contains { $0.ingredients.contains(where: \.isOptional) })
        #expect(recipes.contains { $0.ingredients.contains { $0.unit == .clove } })
        #expect(recipes.contains { $0.tags.contains("mediterranean") })
        #expect(recipes.filter { $0.category == .smoothie }.allSatisfy { $0.mealType == .snack })
    }

    @Test("Diets come from the tags and what a recipe contains")
    func diets() throws {
        for recipe in try RecipeCatalog.bundled() {
            if recipe.diets.contains(.vegan) {
                #expect(recipe.contains.isDisjoint(with: [.meat, .poultry, .pork, .fish, .shellfish, .molluscs, .dairy, .egg]), "\(recipe.id)")
            }
            if recipe.diets.contains(.vegetarian) {
                #expect(recipe.contains.isDisjoint(with: [.meat, .poultry, .pork, .fish, .shellfish, .molluscs]), "\(recipe.id)")
            }
        }
    }

    @Test("The catalog loads once, in the background")
    @MainActor
    func loads() async {
        let catalog = RecipeCatalog()
        #expect(!catalog.isLoaded && catalog.recipes.isEmpty)
        await catalog.load()
        #expect(catalog.isLoaded && catalog.recipes.count == 122)
        #expect(catalog.recipe(id: MockData.tonightRecipeID)?.name == "Miso-glazed cod with greens")
    }

    @Test("Amounts read as written: grams, cloves, pinches, pieces, to taste")
    func amounts() {
        #expect(Recipe.Ingredient(name: "Beans", quantity: 240, unit: .gram).amountText() == "240 g")
        #expect(Recipe.Ingredient(name: "Garlic", quantity: 2, unit: .clove).amountText() == "2 cloves")
        #expect(Recipe.Ingredient(name: "Garlic", quantity: 1, unit: .clove).amountText(scale: 2) == "2 cloves")
        #expect(Recipe.Ingredient(name: "Chilli", quantity: 1, unit: .pinch).amountText() == "1 pinch")
        #expect(Recipe.Ingredient(name: "Eggs", quantity: 4, unit: .piece).amountText() == "4")
        #expect(Recipe.Ingredient(name: "Salt").amountText() == nil)
    }

    private func userRecipe(_ name: String, origin: Recipe.Origin = .user, at date: Date = .now) -> Recipe {
        Recipe(
            id: UUID().uuidString, name: name, category: .lunch, minutes: 20, extraTime: nil, servings: 2,
            nutrition: NutritionFacts(calories: 460, proteinGrams: 24, carbohydrateGrams: 58, fatGrams: 12),
            ingredients: [.init(name: "Baby spinach", key: "baby spinach", quantity: 150, unit: .gram, grams: 150, source: .user,
                                per100: NutritionFacts(calories: 23, proteinGrams: 2.9, carbohydrateGrams: 3.6, fatGrams: 0.4))],
            steps: ["Wilt the spinach."], tip: nil, dietTags: [.vegan], tags: [], highProtein: true, contains: [],
            allergens: [], photo: nil, origin: origin, createdAt: date
        )
    }

    @Test("User and AI recipes are stored here with their photo; export and Delete all include them")
    @MainActor
    func storage() throws {
        let store = try LocalStore.inMemory()
        let stew = userRecipe("Spinach and white bean stew", origin: .ai, at: .now.addingTimeInterval(-60))
        let pie = userRecipe("Salmon and leek pie")
        try store.save(stew, photo: Data([1, 2, 3]))
        try store.save(pie)
        #expect(store.userRecipes.map(\.name) == ["Salmon and leek pie", "Spinach and white bean stew"])
        #expect(store.userRecipes.last?.origin == .ai)
        #expect(store.recipePhoto(id: stew.id) == Data([1, 2, 3]))

        var renamed = stew
        renamed.name = "Bean stew"
        try store.save(renamed)
        #expect(store.userRecipes.count == 2)
        #expect(store.recipePhoto(id: stew.id) == Data([1, 2, 3]), "Saving without a photo keeps it")
        try store.save(renamed, removePhoto: true)
        #expect(store.recipePhoto(id: stew.id) == nil)

        let export = try #require(try JSONSerialization.jsonObject(with: store.exportData(now: .now)) as? [String: Any])
        #expect((export["recipes"] as? [Any])?.count == 2)

        try store.deleteRecipe(id: pie.id)
        #expect(store.userRecipes.map(\.id) == [stew.id])
        try store.deleteAllData()
        #expect(store.userRecipes.isEmpty)
    }

    @Test("A store from the previous build (no recipe entity) opens and takes recipes")
    @MainActor
    func opensPreviousStore() throws {
        let url = URL.temporaryDirectory.appending(path: "previous-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let previous = Schema([
            StoredProfile.self, StoredFoodLogEntry.self, StoredHydrationLog.self, StoredFood.self,
            StoredInventoryItem.self, StoredPlannedMeal.self, StoredGroceryItem.self, StoredWorkout.self, StoredSupplement.self,
            StoredCycleDay.self, StoredHabit.self, StoredHabitCheck.self, StoredSupplementLog.self, StoredCoachMessage.self,
        ])
        let profile = MockData(now: .now, calendar: calendar).profile
        do {
            let context = ModelContext(try ModelContainer(for: previous, configurations: ModelConfiguration(url: url)))
            context.insert(StoredProfile(id: profile.id, payload: try JSONEncoder().encode(profile)))
            try context.save()
        }
        let store = try LocalStore.onDisk(at: url)
        #expect(store.profile?.id == profile.id && store.userRecipes.isEmpty)
        try store.save(userRecipe("Tuna niçoise"))
        #expect(store.userRecipes.count == 1)
    }

    @Test("Log entries from earlier builds have no recipe; cooking a recipe records it and counts")
    @MainActor
    func cookedCount() throws {
        let old = Data("""
        {"id":"6F1C2E1A-7D0B-4E43-9C55-1B0D7A3C9E12","userID":"6F1C2E1A-7D0B-4E43-9C55-1B0D7A3C9E11","foodName":"Skyr",
        "mealType":"breakfast","quantity":150,"servingUnit":"gram","loggedAt":0,
        "nutrition":{"calories":95,"proteinGrams":16,"carbohydrateGrams":6,"fatGrams":0.3,"additional":{}}}
        """.utf8)
        #expect(try JSONDecoder().decode(FoodLogEntry.self, from: old).recipeID == nil)

        let store = try LocalStore.inMemory()
        try store.saveProfile(MockData(now: .now, calendar: calendar).profile)
        let cod = try #require(MockData.catalogRecipes.first { $0.id == MockData.tonightRecipeID })
        let meal = PlannedMeal(candidate: .init(recipe: cod), day: .now, meal: .dinner, now: .now, calendar: calendar)
        try PlanLogging.log(meal, store: store, undo: FoodLogUndo(), calendar: calendar, markPlanned: false)
        try PlanLogging.log(meal, store: store, undo: FoodLogUndo(), calendar: calendar, markPlanned: false)
        #expect(store.cookedCount(recipeID: cod.id) == 2)
        #expect(store.cookedCount(recipeID: "other") == 0)
    }
}
