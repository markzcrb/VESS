import Foundation

/// Where a recipe's photo comes from: one lookup for every screen that
/// shows a recipe (Plan, Today, Recipes, Saved, AI Chef). Discover recipes
/// use their bundled photo; the user's own and saved AI recipes use the
/// photo the user added, if any. `nil` means the quiet tile. Pure.
nonisolated enum RecipePhoto: Equatable, Sendable {
    /// An image in the asset catalog (`RecipePhotos`).
    case bundled(String)
    /// The user's photo, stored with the recipe of this id.
    case user(String)

    static func of(_ recipe: Recipe, hasUserPhoto: (String) -> Bool) -> RecipePhoto? {
        if recipe.origin == .discover {
            return recipe.photo.map(RecipePhoto.bundled)
        }
        return hasUserPhoto(recipe.id) ? .user(recipe.id) : nil
    }

    /// A planned or logged meal's recipe, by id: the catalog first, then
    /// the user's recipes (copies such as Plan's keep only the id).
    static func lookup(recipeID: String, catalog: [Recipe], userRecipes: [Recipe], hasUserPhoto: (String) -> Bool) -> RecipePhoto? {
        guard let recipe = catalog.first(where: { $0.id == recipeID }) ?? userRecipes.first(where: { $0.id == recipeID }) else { return nil }
        return of(recipe, hasUserPhoto: hasUserPhoto)
    }
}
