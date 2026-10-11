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
    var quantity: Double
    var servingUnit: QuantityUnit
    var nutrition: NutritionFacts
    var loggedAt: Date
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
            loggedAt: loggedAt
        )
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
