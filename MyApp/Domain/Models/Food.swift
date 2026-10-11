import Foundation

/// A food definition: a database item, a scanned product or a user-created food.
nonisolated struct Food: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    /// The reference amount that `nutrition` describes, such as 100 g.
    var servingSize: Double
    var servingUnit: QuantityUnit
    /// Nutrition for one `servingSize` in `servingUnit`.
    var nutrition: NutritionFacts
    var ingredients: [String]
    var allergens: Set<Allergen>
    var quality: FoodQuality?
    var source: FoodSource
    let createdAt: Date
    var updatedAt: Date

    /// Nutrition for `quantity`, expressed in this food's `servingUnit`.
    func nutrition(forQuantity quantity: Double) -> NutritionFacts {
        guard servingSize > 0 else { return .zero }
        return nutrition.scaled(by: quantity / servingSize)
    }
}

nonisolated enum Allergen: String, Codable, CaseIterable, Sendable {
    case gluten
    case lactose
    case nuts
    case soy
    case eggs
}

/// Where a food's data came from. AI estimates are always labeled as estimates in the UI.
nonisolated enum FoodSource: String, Codable, Sendable {
    case userCreated
    case foodDatabase
    case barcodeScan
    case aiEstimate
}

/// Ingredient-level quality metadata. Descriptive only, never a health verdict.
nonisolated struct FoodQuality: Codable, Hashable, Sendable {
    var processingLevel: ProcessingLevel?
    var additives: [String]
}

/// Degree of processing, aligned with the NOVA classification groups.
nonisolated enum ProcessingLevel: String, Codable, CaseIterable, Sendable {
    case unprocessed
    case processedIngredient
    case processed
    case ultraProcessed
}
