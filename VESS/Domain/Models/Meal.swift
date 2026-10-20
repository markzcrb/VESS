import Foundation

/// A reusable or planned combination of foods, such as "Usual breakfast".
/// Logging a meal creates one `FoodLogEntry` per component.
nonisolated struct Meal: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var suggestedMealType: MealType?
    var components: [Component]
    var notes: String?
    let createdAt: Date
    var updatedAt: Date

    var totalNutrition: NutritionFacts { components.map(\.nutrition).total }

    nonisolated struct Component: Identifiable, Codable, Hashable, Sendable {
        let id: UUID
        var foodID: UUID
        var foodName: String
        var quantity: Double
        var servingUnit: QuantityUnit
        var nutrition: NutritionFacts
    }
}
