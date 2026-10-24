import Foundation

/// Nutrition per serving from a recipe's ingredients. Pure and
/// deterministic; the AI never supplies these numbers.
nonisolated enum RecipeNutritionCalculator {
    /// `perServing = Σ(per100 × grams / 100) / servings`.
    ///
    /// - `per100` looks up USDA foods by NDB number; label, user and Open Food
    ///   Facts ingredients carry their own values.
    /// - An ingredient without values or grams makes the total partial
    ///   (`isPartial`): the other ingredients still count, and fibre, sugar
    ///   and sodium become unknown.
    /// - Unknown fibre, sugar or sodium on any ingredient leaves that value
    ///   unknown in the total, never 0 (as in `NutritionFacts`).
    static func perServing(
        ingredients: [Recipe.Ingredient],
        servings: Int,
        per100: (String) -> NutritionFacts?
    ) -> (nutrition: NutritionFacts, isPartial: Bool) {
        var total = NutritionFacts.zero
        var fiber: Double? = 0, sugar: Double? = 0, sodium: Double? = 0, saturatedFat: Double? = 0
        var unreported = Set<CoreNutrient>()
        var isPartial = false

        for ingredient in ingredients {
            guard let grams = ingredient.grams, let values = values(for: ingredient, per100: per100) else {
                // "No nutrition data · Choose food": the rest still adds up,
                // and the total says "Partial".
                isPartial = true
                fiber = nil; sugar = nil; sodium = nil; saturatedFat = nil
                continue
            }
            let factor = grams / 100
            total.calories += values.calories * factor
            total.proteinGrams += values.proteinGrams * factor
            total.carbohydrateGrams += values.carbohydrateGrams * factor
            total.fatGrams += values.fatGrams * factor
            unreported.formUnion(values.unreportedCoreNutrients ?? [])
            fiber = add(fiber, values.fiberGrams, factor)
            sugar = add(sugar, values.sugarGrams, factor)
            sodium = add(sodium, values.sodiumMilligrams, factor)
            saturatedFat = add(saturatedFat, values.additional[.saturatedFat], factor)
        }

        let divisor = Double(max(servings, 1))
        var result = NutritionFacts(
            calories: total.calories / divisor,
            proteinGrams: total.proteinGrams / divisor,
            carbohydrateGrams: total.carbohydrateGrams / divisor,
            fatGrams: total.fatGrams / divisor,
            fiberGrams: fiber.map { $0 / divisor },
            sugarGrams: sugar.map { $0 / divisor },
            sodiumMilligrams: sodium.map { $0 / divisor }
        )
        if let saturatedFat { result.additional[.saturatedFat] = saturatedFat / divisor }
        result.unreportedCoreNutrients = unreported.isEmpty ? nil : unreported
        return (result, isPartial)
    }

    /// Per 100 g for an ingredient: USDA by number, else its own values.
    static func values(for ingredient: Recipe.Ingredient, per100: (String) -> NutritionFacts?) -> NutritionFacts? {
        if case .usda(let ndb) = ingredient.source, let values = per100(ndb) { return values }
        return ingredient.per100
    }

    /// High protein, as in the data: at least 20 g per serving, or at least
    /// 15 g that is at least 30 % of the energy.
    static func isHighProtein(_ nutrition: NutritionFacts) -> Bool {
        guard nutrition.isReported(.protein), nutrition.isReported(.calories) else { return false }
        let protein = nutrition.proteinGrams
        if protein >= 20 { return true }
        return protein >= 15 && nutrition.calories > 0 && protein * 4 / nutrition.calories >= 0.30
    }

    private static func add(_ sum: Double?, _ value: Double?, _ factor: Double) -> Double? {
        guard let sum, let value else { return nil }
        return sum + value * factor
    }
}
