import Foundation

nonisolated struct UserProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// Stored instead of age so the value never goes stale. See `age(on:calendar:)`.
    var dateOfBirth: Date?
    var sex: Sex
    var heightCentimeters: Double
    var weightKilograms: Double
    var goalWeightKilograms: Double?
    var goal: WellnessGoal
    var activityLevel: ActivityLevel
    var dietaryPreference: DietaryPreference
    /// Free-text description when `dietaryPreference` is `.custom`.
    var customDietDescription: String?
    var allergies: Set<Allergen>
    /// Restrictions not covered by `Allergen` ("Other" in onboarding).
    var otherRestrictions: [String]
    var focusAreas: Set<FocusArea>
    var nutritionTargets: NutritionTargets
    var waterTargetMilliliters: Double
    let createdAt: Date
    var updatedAt: Date
    /// The user's own hydration contribution defaults, per drink.
    var hydrationContributionOverrides: [DrinkPreset: Double]? = nil
    /// Whether the user wants Apple Health. Recorded in onboarding; permission
    /// is requested later, in context, never during onboarding.
    var prefersAppleHealth: Bool? = nil
    /// Daily steps goal; `nil` uses `defaultStepsTarget`.
    var stepsTarget: Int? = nil

    static let defaultStepsTarget = 8_000

    var dailyStepsTarget: Int { stepsTarget ?? Self.defaultStepsTarget }

    func age(on date: Date, calendar: Calendar) -> Int? {
        guard let dateOfBirth else { return nil }
        return calendar.dateComponents([.year], from: dateOfBirth, to: date).year
    }

    /// The hydration contribution to use for `preset`: the user's own value if set.
    func hydrationContributionPercent(for preset: DrinkPreset) -> Double {
        hydrationContributionOverrides?[preset] ?? preset.defaultHydrationContributionPercent
    }
}

/// Used only to estimate energy needs. `.notSpecified` is always allowed.
nonisolated enum Sex: String, Codable, CaseIterable, Sendable {
    case female
    case male
    case notSpecified
}

nonisolated enum WellnessGoal: String, Codable, CaseIterable, Sendable {
    case loseWeight
    case maintainWeight
    case gainWeight
    case buildMuscle
    case eatHealthier
    case improveEnergy
    case improveConsistency
}

nonisolated enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive
}

nonisolated enum DietaryPreference: String, Codable, CaseIterable, Sendable {
    case everything
    case vegetarian
    case vegan
    case highProtein
    case lowCarb
    case custom
}

/// What the user wants VESS to focus on ("What matters to you?").
nonisolated enum FocusArea: String, Codable, CaseIterable, Sendable {
    case nutrition
    case fitness
    case energy
    case hydration
    case budget
    case foodWaste
    case mealPlanning
}

/// Daily targets. Calculated deterministically (never by AI) and editable by the user.
nonisolated struct NutritionTargets: Codable, Hashable, Sendable {
    var calories: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
}
