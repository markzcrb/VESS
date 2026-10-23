import Foundation

/// `200 { items, note, remaining, estimated }` from the food-photo function.
nonisolated struct PhotoEstimateResponse: Decodable, Equatable, Sendable {
    struct Item: Decodable, Equatable, Sendable {
        let name: String
        let amount: Double
        let unit: String
        let kcal: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let confidence: String

        enum CodingKeys: String, CodingKey {
            case name, amount, unit, kcal, confidence
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
        }
    }

    let items: [Item]
    let note: String?
    let remaining: Int?
}

/// One item on the review screen. Nutrition is kept per unit (g or ml), so
/// changing the amount scales everything; the server's confidence stays.
nonisolated struct EstimatedItem: Identifiable, Equatable, Sendable {
    enum Confidence: String, Sendable { case high, medium, low }

    let id: UUID
    var name: String
    var amount: Double
    var isMilliliters: Bool
    /// Per gram or millilitre.
    var perUnit: NutritionFacts
    var confidence: Confidence

    /// Low confidence is highlighted as "Check this".
    var needsCheck: Bool { confidence == .low }

    var nutrition: NutritionFacts { perUnit.scaled(by: amount) }

    /// 10 g or ml at a time, never below 1.
    static let step: Double = 10

    init(id: UUID = UUID(), name: String, amount: Double, isMilliliters: Bool, perUnit: NutritionFacts, confidence: Confidence) {
        self.id = id
        self.name = name
        self.amount = amount
        self.isMilliliters = isMilliliters
        self.perUnit = perUnit
        self.confidence = confidence
    }

    init(_ item: PhotoEstimateResponse.Item) {
        let amount = max(item.amount, 1)
        self.init(
            name: item.name,
            amount: item.amount > 0 ? item.amount : 100,
            isMilliliters: item.unit == "ml",
            perUnit: NutritionFacts(
                calories: item.kcal / amount, proteinGrams: item.proteinG / amount,
                carbohydrateGrams: item.carbsG / amount, fatGrams: item.fatG / amount
            ),
            confidence: Confidence(rawValue: item.confidence) ?? .low
        )
    }
}

nonisolated enum PhotoEstimateRules {
    static func items(from response: PhotoEstimateResponse) -> [EstimatedItem] {
        response.items.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map(EstimatedItem.init)
    }

    static func stepped(_ amount: Double, by direction: Int) -> Double {
        max(1, ((amount / EstimatedItem.step).rounded() + Double(direction)) * EstimatedItem.step)
    }

    static func total(_ items: [EstimatedItem]) -> NutritionFacts {
        items.map(\.nutrition).total
    }

    /// The entries Save adds, one per item, marked as estimated from a photo.
    /// Items without a name or amount are left out.
    static func entries(_ items: [EstimatedItem], userID: UUID, meal: MealType, at date: Date) -> [FoodLogEntry] {
        items.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, item.amount > 0 else { return nil }
            return FoodLogEntry(
                id: UUID(), userID: userID, foodID: nil, foodName: name, mealType: meal,
                quantity: item.amount, servingUnit: item.isMilliliters ? .milliliter : .gram,
                nutrition: item.nutrition, loggedAt: date, source: .photoEstimate
            )
        }
    }
}
