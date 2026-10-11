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
/// Fiber, sugar and sodium are optional because many sources don't report
/// them, and "unknown" must not be shown as zero. The four core values are
/// stored as numbers, but a source can leave one unreported: it is then listed
/// in `unreportedCoreNutrients`, its stored value is 0 only as a placeholder,
/// and the UI shows "Not reported" instead of a number.
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
    /// Core values the source did not report. `nil` (older data) means all reported.
    var unreportedCoreNutrients: Set<CoreNutrient>? = nil

    static let zero = NutritionFacts(calories: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
}

/// The four values every VESS nutrition summary is built on.
nonisolated enum CoreNutrient: String, Codable, CaseIterable, Sendable {
    case calories
    case protein
    case carbohydrates
    case fat
}

nonisolated extension NutritionFacts {
    /// Whether `nutrient` has a real, reported value.
    func isReported(_ nutrient: CoreNutrient) -> Bool {
        !(unreportedCoreNutrients?.contains(nutrient) ?? false)
    }

    /// Calories are required to log a food: without them it can't count
    /// toward the day.
    var canBeLogged: Bool { isReported(.calories) }

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
            additional: additional.mapValues { $0 * factor },
            unreportedCoreNutrients: unreportedCoreNutrients
        )
    }

    /// Sums two sets of values. An optional nutrient is known in the result
    /// if either side knows it. A core nutrient unreported on either side is
    /// unreported in the total, so the total is never presented as complete.
    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        let unreported = (lhs.unreportedCoreNutrients ?? []).union(rhs.unreportedCoreNutrients ?? [])
        return NutritionFacts(
            calories: lhs.calories + rhs.calories,
            proteinGrams: lhs.proteinGrams + rhs.proteinGrams,
            carbohydrateGrams: lhs.carbohydrateGrams + rhs.carbohydrateGrams,
            fatGrams: lhs.fatGrams + rhs.fatGrams,
            fiberGrams: sum(lhs.fiberGrams, rhs.fiberGrams),
            sugarGrams: sum(lhs.sugarGrams, rhs.sugarGrams),
            sodiumMilligrams: sum(lhs.sodiumMilligrams, rhs.sodiumMilligrams),
            additional: lhs.additional.merging(rhs.additional, uniquingKeysWith: +),
            unreportedCoreNutrients: unreported.isEmpty ? nil : unreported
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
