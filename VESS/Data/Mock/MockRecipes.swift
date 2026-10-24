import Foundation

#if DEBUG
/// R02's kitchen, for DEBUG captures (`-recipesDemo`): six of Mark's own
/// recipes, two saved from AI Chef, pescatarian and nut-free, cooked on
/// earlier days. Nutrition is calculated from USDA values, never typed.
nonisolated extension MockData {
    @MainActor
    static func seedRecipes(into store: LocalStore, now: Date, calendar: Calendar) throws {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        func copy(_ id: String, as newID: String, origin: Recipe.Origin, created: Int) -> Recipe? {
            guard var recipe = catalogRecipes.first(where: { $0.id == id }) else { return nil }
            recipe = Recipe(
                id: newID, name: recipe.name, category: recipe.category, minutes: recipe.minutes, extraTime: recipe.extraTime,
                servings: recipe.servings, nutrition: recipe.nutrition, ingredients: recipe.ingredients, steps: recipe.steps,
                tip: recipe.tip, dietTags: recipe.dietTags, tags: recipe.tags, highProtein: recipe.highProtein,
                contains: recipe.contains, allergens: recipe.allergens, photo: nil, origin: origin, createdAt: day(created)
            )
            return recipe
        }

        func usda(_ name: String, _ ndb: String, grams: Double, unit: Recipe.Unit = .gram, quantity: Double? = nil, allergens: Set<Allergen> = []) -> Recipe.Ingredient {
            Recipe.Ingredient(
                name: name, key: name.lowercased(), quantity: quantity ?? grams, unit: unit, grams: grams, allergens: allergens,
                source: .usda(ndb: ndb), per100: genericFoods[ndb]?.per100g
            )
        }
        let pieIngredients = [
            usda("Salmon fillets", "15236", grams: 500, allergens: [.fish]),
            usda("Leeks", "11246", grams: 300),
            usda("Potatoes", "11354", grams: 800),
            usda("Whole milk", "01077", grams: 300, unit: .milliliter, quantity: 300, allergens: [.milk]),
            usda("Butter", "01001", grams: 40, allergens: [.milk]),
            usda("Plain flour", "20481", grams: 30, unit: .tablespoon, quantity: 3, allergens: [.gluten]),
            usda("Fresh dill", "02045", grams: 5),
        ]
        let pieNutrition = RecipeNutritionCalculator.perServing(ingredients: pieIngredients, servings: 4) { genericFoods[$0]?.per100g }.nutrition
        let pie = Recipe(
            id: "mine-salmon-leek-pie", name: "Salmon and leek pie", category: .dinner, minutes: 50, extraTime: nil, servings: 4,
            nutrition: pieNutrition, ingredients: pieIngredients,
            steps: [
                "Boil the potatoes until soft, then mash with a little of the milk.",
                "Soften the leeks in the butter, stir in the flour, then the rest of the milk until it thickens.",
                "Fold in the salmon in chunks and the dill. Spoon into a dish and top with the mash.",
                "Bake at 200 °C for 25 minutes until golden.",
            ],
            tip: nil, dietTags: [.pescatarian], tags: [], highProtein: RecipeNutritionCalculator.isHighProtein(pieNutrition),
            contains: [.fish, .dairy], allergens: [.fish, .milk, .gluten], photo: nil, origin: .user, createdAt: day(-40)
        )

        let recipes = [
            pie,
            copy("010-spinach-and-white-bean-stew", as: "mine-spinach-bean-stew", origin: .ai, created: -12),
            copy("006-protein-pancakes-with-banana", as: "mine-protein-pancakes", origin: .user, created: -30),
            copy("045-chia-pudding-with-mango", as: "mine-chia-pudding", origin: .user, created: -25),
            copy("032-cod-lentils-and-roasted-carrots", as: "mine-cod-lentils", origin: .ai, created: -8),
            copy("012-tuna-nicoise", as: "mine-tuna-nicoise", origin: .user, created: -20),
        ].compactMap(\.self)
        for recipe in recipes { try store.save(recipe) }

        // Cooked on earlier days: the pie three times, the stew and the pancakes once.
        guard let profile = store.profile else { return }
        let cooked: [(Recipe, Int)] = [(pie, -3), (pie, -10), (pie, -17), (recipes[1], -2), (recipes[2], -5)]
        for (recipe, offset) in cooked {
            try store.add(FoodLogEntry(
                id: UUID(), userID: profile.id, foodID: nil, foodName: recipe.name, mealType: recipe.mealType,
                quantity: 1, servingUnit: .serving, nutrition: recipe.nutrition,
                loggedAt: recipe.mealType.logTime(on: day(offset), calendar: calendar), recipeID: recipe.id
            ))
        }
    }
}
#endif
