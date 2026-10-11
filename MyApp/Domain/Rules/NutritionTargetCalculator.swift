import Foundation

/// Calculates starting daily targets from a profile. Deterministic and
/// unit-tested; never delegated to AI. Users can edit every result.
///
/// - Energy: Mifflin-St Jeor resting energy × activity factor × goal adjustment.
/// - Protein: grams per kg of body weight, by goal and diet.
/// - Fat: a share of energy. Carbohydrates: the remainder.
/// - Water: 33 ml per kg, clamped to a sensible range.
nonisolated enum NutritionTargetCalculator {
    /// Lowest energy target VESS will suggest. Below this, users should set
    /// targets with a professional rather than rely on a formula.
    static let minimumCalories: Double = 1200

    struct Input: Sendable {
        var sex: Sex
        var ageYears: Int
        var heightCentimeters: Double
        var weightKilograms: Double
        var activityLevel: ActivityLevel
        var goal: WellnessGoal
        var dietaryPreference: DietaryPreference
    }

    static func targets(for input: Input) -> NutritionTargets {
        let calories = max(
            round(dailyEnergy(for: input), toNearest: 50),
            minimumCalories
        )
        let protein = round(input.weightKilograms * proteinPerKilogram(goal: input.goal, diet: input.dietaryPreference), toNearest: 5)
        let fatShare = input.dietaryPreference == .lowCarb ? 0.35 : 0.28
        let fat = round(calories * fatShare / 9, toNearest: 5)
        let carbohydrates = max(round((calories - protein * 4 - fat * 9) / 4, toNearest: 5), 0)

        return NutritionTargets(
            calories: calories,
            proteinGrams: protein,
            carbohydrateGrams: carbohydrates,
            fatGrams: fat
        )
    }

    static func waterTargetMilliliters(weightKilograms: Double) -> Double {
        min(max(round(weightKilograms * 33, toNearest: 100), 1500), 4000)
    }

    /// Mifflin-St Jeor resting energy in kcal. "Not specified" uses the
    /// midpoint of the two sex-specific constants.
    static func restingEnergy(for input: Input) -> Double {
        let base = 10 * input.weightKilograms + 6.25 * input.heightCentimeters - 5 * Double(input.ageYears)
        switch input.sex {
        case .male: return base + 5
        case .female: return base - 161
        case .notSpecified: return base - 78
        }
    }

    static func dailyEnergy(for input: Input) -> Double {
        restingEnergy(for: input) * activityFactor(input.activityLevel) * goalAdjustment(input.goal)
    }

    static func activityFactor(_ level: ActivityLevel) -> Double {
        switch level {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    static func goalAdjustment(_ goal: WellnessGoal) -> Double {
        switch goal {
        case .loseWeight: 0.85
        case .gainWeight, .buildMuscle: 1.10
        case .maintainWeight, .eatHealthier, .improveEnergy, .improveConsistency: 1.0
        }
    }

    static func proteinPerKilogram(goal: WellnessGoal, diet: DietaryPreference) -> Double {
        let byGoal: Double = switch goal {
        case .buildMuscle: 1.8
        case .loseWeight, .gainWeight: 1.6
        case .maintainWeight, .eatHealthier, .improveEnergy, .improveConsistency: 1.2
        }
        return diet == .highProtein ? max(byGoal, 1.8) : byGoal
    }

    private static func round(_ value: Double, toNearest step: Double) -> Double {
        (value / step).rounded() * step
    }
}
