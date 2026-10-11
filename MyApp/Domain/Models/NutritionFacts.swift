import Foundation

/// Identifier for a nutrient outside the core set, such as a vitamin.
/// New nutrients are added as constants without changing any schema.
nonisolated struct NutrientID: RawRepresentable, Hashable, Codable, CodingKeyRepresentable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let saturatedFat = NutrientID(rawValue: "saturated_fat")
    static let potassium = NutrientID(rawValue: "potassium")
    static let calcium = NutrientID(rawValue: "calcium")
    static let iron = NutrientID(rawValue: "iron")
    static let vitaminD = NutrientID(rawValue: "vitamin_d")
}

/// Nutrition values for one amount of food.
///
/// The four core values are always present. Fiber, sugar and sodium are
/// optional because many food sources don't report them, and "unknown"
/// must not be shown as zero.
nonisolated struct NutritionFacts: Codable, Hashable, Sendable {
    var calories: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
    var fiberGrams: Double?
    var sugarGrams: Double?
    var sodiumMilligrams: Double?
    /// Any other nutrients, keyed by identifier. Units are per `NutrientID` convention.
    var additional: [NutrientID: Double] = [:]

    static let zero = NutritionFacts(calories: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
}

nonisolated extension NutritionFacts {
    /// Returns these values multiplied by `factor`, for example 1.5 servings.
    func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(
            calories: calories * factor,
            proteinGrams: proteinGrams * factor,
            carbohydrateGrams: carbohydrateGrams * factor,
            fatGrams: fatGrams * factor,
            fiberGrams: fiberGrams.map { $0 * factor },
            sugarGrams: sugarGrams.map { $0 * factor },
            sodiumMilligrams: sodiumMilligrams.map { $0 * factor },
            additional: additional.mapValues { $0 * factor }
        )
    }

    /// Sums two sets of values. An optional nutrient is known in the result
    /// if either side knows it.
    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            calories: lhs.calories + rhs.calories,
            proteinGrams: lhs.proteinGrams + rhs.proteinGrams,
            carbohydrateGrams: lhs.carbohydrateGrams + rhs.carbohydrateGrams,
            fatGrams: lhs.fatGrams + rhs.fatGrams,
            fiberGrams: sum(lhs.fiberGrams, rhs.fiberGrams),
            sugarGrams: sum(lhs.sugarGrams, rhs.sugarGrams),
            sodiumMilligrams: sum(lhs.sodiumMilligrams, rhs.sodiumMilligrams),
            additional: lhs.additional.merging(rhs.additional, uniquingKeysWith: +)
        )
    }

    private static func sum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case (nil, nil): nil
        default: (lhs ?? 0) + (rhs ?? 0)
        }
    }
}

nonisolated extension Sequence where Element == NutritionFacts {
    var total: NutritionFacts { reduce(.zero, +) }
}
