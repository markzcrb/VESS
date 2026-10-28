import Foundation

/// One food logged by the user.
///
/// Name and nutrition are snapshots taken at logging time, so history stays
/// correct if the food is later edited or deleted, and entries work offline.
nonisolated struct FoodLogEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var foodID: UUID?
    var foodName: String
    var mealType: MealType
    /// Amount logged, in `servingUnit`.
    var quantity: Double
    var servingUnit: QuantityUnit
    var nutrition: NutritionFacts
    var loggedAt: Date
    /// The named portion used, such as "1 slice", if any.
    var portionLabel: String? = nil
    /// Size of one `portionLabel` portion in `servingUnit`.
    var portionAmount: Double? = nil
    /// Where the food's data came from when it was logged.
    var source: FoodSource? = nil
    /// The recipe it was cooked from ("Cooked 3×"). `nil` in entries from
    /// earlier builds and for everything else.
    var recipeID: String? = nil
    /// The menu a dish was read from ("The evening menu"), for entries from
    /// a menu scan. `nil` for everything else.
    var menuName: String? = nil
}

nonisolated extension FoodLogEntry {
    /// Creates an entry for `quantity` of `food`, in the food's serving unit.
    init(
        id: UUID = UUID(),
        userID: UUID,
        food: Food,
        quantity: Double,
        mealType: MealType,
        loggedAt: Date
    ) {
        self.init(
            id: id,
            userID: userID,
            foodID: food.id,
            foodName: food.name,
            mealType: mealType,
            quantity: quantity,
            servingUnit: food.servingUnit,
            nutrition: food.nutrition(forQuantity: quantity),
            loggedAt: loggedAt,
            source: food.source
        )
    }

    /// Creates an entry for a chosen portion of `food`, with a nutrition
    /// snapshot so later edits to the food never change history.
    init(
        id: UUID = UUID(),
        userID: UUID,
        food: Food,
        portion: Portion,
        mealType: MealType,
        loggedAt: Date
    ) {
        self.init(id: id, userID: userID, food: food, quantity: portion.baseAmount, mealType: mealType, loggedAt: loggedAt)
        if !portion.option.isBaseUnit {
            portionLabel = portion.option.label
            portionAmount = portion.option.amount
        }
    }

    /// How many portions (or base units) this entry represents, for editing.
    var portionCount: Double {
        guard let portionAmount, portionAmount > 0 else { return quantity }
        return quantity / portionAmount
    }

    /// A copy with a new portion count and meal. Nutrition is rescaled from
    /// this entry's own snapshot, so the result is deterministic and never
    /// depends on the food's current data.
    func updated(portionCount newCount: Double, mealType newMeal: MealType) -> FoodLogEntry {
        var copy = self
        copy.mealType = newMeal
        let newQuantity = (portionAmount ?? 1) * newCount
        guard quantity > 0, newQuantity > 0 else { return copy }
        copy.nutrition = nutrition.scaled(by: newQuantity / quantity)
        copy.quantity = newQuantity
        return copy
    }
}

/// Meal slots. Custom slots can be added later by replacing this enum with
/// a struct that keeps these four as built-in values.
nonisolated enum MealType: String, Codable, CaseIterable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
}

nonisolated extension Sequence where Element == FoodLogEntry {
    var totalNutrition: NutritionFacts { map(\.nutrition).total }

    func entries(for mealType: MealType) -> [FoodLogEntry] {
        filter { $0.mealType == mealType }
    }
}
