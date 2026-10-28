import Foundation

/// The small part of the profile kept in the user's own iCloud (key-value
/// storage), so a new install can skip the questions: goal, sex, birth
/// year, height, weight, activity, diet, allergens, the avoid list and the
/// targets. Never the log, cycle days or the Pregnant switch. Pure.
nonisolated struct MirroredProfile: Codable, Equatable, Sendable {
    static let version = 1

    var version = MirroredProfile.version
    var name: String
    var goal: WellnessGoal
    var sex: Sex
    var birthYear: Int?
    var heightCentimeters: Double
    var weightKilograms: Double
    var goalWeightKilograms: Double?
    var activityLevel: ActivityLevel
    var diet: Diet
    var alsoPrefer: Set<FoodPreference>
    var allergies: Set<Allergen>
    var avoid: [String]
    var targets: NutritionTargets
    var waterTargetMilliliters: Double
    var stepsTarget: Int?
    var sleepTargetMinutes: Int?

    init(_ profile: UserProfile, calendar: Calendar) {
        let preferences = profile.preferences
        name = profile.name
        goal = profile.goal
        sex = profile.sex
        birthYear = profile.dateOfBirth.map { calendar.component(.year, from: $0) }
        heightCentimeters = profile.heightCentimeters
        weightKilograms = profile.weightKilograms
        goalWeightKilograms = profile.goalWeightKilograms
        activityLevel = profile.activityLevel
        diet = preferences.diet
        alsoPrefer = preferences.alsoPrefer
        allergies = profile.allergies
        avoid = preferences.avoidIngredients
        targets = profile.nutritionTargets
        waterTargetMilliliters = profile.waterTargetMilliliters
        stepsTarget = profile.stepsTarget
        sleepTargetMinutes = profile.sleepTargetMinutes
    }

    /// A profile for this iPhone with the same answers and targets. The
    /// birthday is taken as 1 July of the birth year.
    func makeProfile(now: Date, calendar: Calendar) -> UserProfile {
        let chosen = NutritionPreferences(diet: diet, alsoPrefer: alsoPrefer, avoidIngredients: avoid)
        var profile = UserProfile(
            id: UUID(),
            name: name,
            dateOfBirth: birthYear.flatMap { calendar.date(from: DateComponents(year: $0, month: 7, day: 1)) },
            sex: sex,
            heightCentimeters: heightCentimeters,
            weightKilograms: weightKilograms,
            goalWeightKilograms: goalWeightKilograms,
            goal: goal,
            activityLevel: activityLevel,
            dietaryPreference: chosen.targetDiet,
            customDietDescription: nil,
            allergies: allergies,
            otherRestrictions: [],
            focusAreas: [],
            nutritionTargets: targets,
            waterTargetMilliliters: waterTargetMilliliters,
            createdAt: now,
            updatedAt: now,
            stepsTarget: stepsTarget,
            sleepTargetMinutes: sleepTargetMinutes
        )
        profile.nutritionPreferences = chosen
        return profile
    }
}
