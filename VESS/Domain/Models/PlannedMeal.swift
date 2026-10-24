import Foundation

/// A meal planned for a day and slot (Plan). It keeps its own snapshot of
/// what it contains, so later changes to a food don't rewrite the plan.
nonisolated struct PlannedMeal: Identifiable, Codable, Hashable, Sendable {
    /// One thing in the meal, with an amount when known.
    nonisolated struct Item: Codable, Hashable, Sendable {
        var name: String
        var quantity: Double?
        var unit: QuantityUnit?
        /// The saved or catalog food it came from, if any.
        var foodID: UUID?
        /// This item's nutrition, when known (foods); recipes only know the total.
        var nutrition: NutritionFacts?
    }

    nonisolated enum Source: Codable, Hashable, Sendable {
        /// Saved foods, or a meal the user logged before.
        case foods
        /// A recipe, by its identifier.
        case recipe(String)
    }

    let id: UUID
    /// The start of the planned day.
    var day: Date
    var mealType: MealType
    var name: String
    /// Total for the meal (one serving).
    var nutrition: NutritionFacts
    var items: [Item]
    var source: Source
    /// Set once it has been logged from the plan.
    var loggedAt: Date?
    let createdAt: Date
}
