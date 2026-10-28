import Foundation
import Testing
@testable import VESS

@Suite("Recipe photos: one lookup for every screen")
struct RecipePhotoTests {
    private func catalog() throws -> [Recipe] {
        try RecipeCatalog.bundled()
    }

    private func userCopy(of recipe: Recipe, id: String, origin: Recipe.Origin) -> Recipe {
        Recipe(id: id, name: recipe.name, category: recipe.category, minutes: recipe.minutes, extraTime: recipe.extraTime,
               servings: recipe.servings, nutrition: recipe.nutrition, ingredients: recipe.ingredients, steps: recipe.steps,
               tip: recipe.tip, dietTags: recipe.dietTags, tags: recipe.tags, highProtein: recipe.highProtein,
               contains: recipe.contains, allergens: recipe.allergens, photo: nil, origin: origin, createdAt: .now)
    }

    @Test("A planned Discover recipe resolves to its bundled photo, by id alone")
    func plannedCatalogRecipe() throws {
        let recipes = try catalog()
        let recipe = try #require(recipes.first { $0.photo != nil })
        // Plan keeps only `.recipe(id)`; the meal itself is a copy without a photo.
        let meal = PlannedMeal(candidate: .init(recipe: recipe), day: .now, meal: recipe.mealType, now: .now, calendar: .current)
        guard case .recipe(let id) = meal.source else { Issue.record("Not a recipe meal"); return }
        let photo = RecipePhoto.lookup(recipeID: id, catalog: recipes, userRecipes: []) { _ in false }
        #expect(photo == .bundled(try #require(recipe.photo)))
    }

    @Test("A planned user recipe resolves to the user's photo; without one, the quiet tile")
    func plannedUserRecipe() throws {
        let base = try #require(try catalog().first)
        let mine = userCopy(of: base, id: "mine-test", origin: .user)
        let meal = PlannedMeal(candidate: .init(recipe: mine), day: .now, meal: mine.mealType, now: .now, calendar: .current)
        guard case .recipe(let id) = meal.source else { Issue.record("Not a recipe meal"); return }
        #expect(RecipePhoto.lookup(recipeID: id, catalog: [], userRecipes: [mine]) { $0 == "mine-test" } == .user("mine-test"))
        #expect(RecipePhoto.lookup(recipeID: id, catalog: [], userRecipes: [mine]) { _ in false } == nil)
    }

    @Test("Saved AI recipes use the user's photo too; an unknown id has none")
    func aiAndUnknown() throws {
        let base = try #require(try catalog().first)
        let ai = userCopy(of: base, id: "ai-test", origin: .ai)
        #expect(RecipePhoto.of(ai) { _ in true } == .user("ai-test"))
        #expect(RecipePhoto.lookup(recipeID: "nope", catalog: [base], userRecipes: [ai]) { _ in true } == nil)
    }
}
