import Foundation
import Observation

/// The steps of onboarding, in order. One question per screen.
enum OnboardingStep: Int, CaseIterable, Comparable {
    case welcome
    case goal
    case basics
    case activity
    case diet
    case restrictions
    case focus
    case appleHealth

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Steps that show the progress line (everything after Welcome).
    static let questions = allCases.filter { $0 != .welcome }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

/// Answers collected during onboarding, turned into a `UserProfile` at the end.
@Observable
final class OnboardingDraft {
    var name = ""
    var goal: WellnessGoal?
    var ageText = ""
    var sex: Sex?
    var heightText = ""
    var weightText = ""
    var activityLevel: ActivityLevel?
    var dietaryPreference: DietaryPreference?
    var customDiet = ""
    var allergies: Set<Allergen> = []
    var otherRestriction = ""
    var focusAreas: Set<FocusArea> = []

    static let ageRange = 13...100
    static let heightRange = 100.0...250.0
    static let weightRange = 30.0...300.0

    var age: Int? {
        guard let value = Int(ageText.trimmingCharacters(in: .whitespaces)), Self.ageRange.contains(value) else { return nil }
        return value
    }

    var heightCentimeters: Double? {
        guard let value = VESSFormat.number(from: heightText), Self.heightRange.contains(value) else { return nil }
        return value
    }

    var weightKilograms: Double? {
        guard let value = VESSFormat.number(from: weightText), Self.weightRange.contains(value) else { return nil }
        return value
    }

    /// Whether the user can continue past `step`. Optional steps are always complete.
    func isComplete(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome, .restrictions, .focus, .appleHealth:
            return true
        case .goal:
            return goal != nil
        case .basics:
            return age != nil && sex != nil && heightCentimeters != nil && weightKilograms != nil
        case .activity:
            return activityLevel != nil
        case .diet:
            guard let dietaryPreference else { return false }
            return dietaryPreference != .custom || !customDiet.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// Builds the profile with calculated starting targets, or `nil` if a
    /// required answer is missing.
    func makeProfile(prefersAppleHealth: Bool, now: Date, calendar: Calendar) -> UserProfile? {
        guard let goal, let age, let sex, let heightCentimeters, let weightKilograms,
              let activityLevel, let dietaryPreference else { return nil }

        let input = NutritionTargetCalculator.Input(
            sex: sex,
            ageYears: age,
            heightCentimeters: heightCentimeters,
            weightKilograms: weightKilograms,
            activityLevel: activityLevel,
            goal: goal,
            dietaryPreference: dietaryPreference
        )
        let restriction = otherRestriction.trimmingCharacters(in: .whitespacesAndNewlines)
        let diet = customDiet.trimmingCharacters(in: .whitespacesAndNewlines)

        return UserProfile(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            // Onboarding asks for age, not a birthday; store an approximate
            // date of birth so age stays current over time.
            dateOfBirth: calendar.date(byAdding: .year, value: -age, to: now),
            sex: sex,
            heightCentimeters: heightCentimeters,
            weightKilograms: weightKilograms,
            goalWeightKilograms: nil,
            goal: goal,
            activityLevel: activityLevel,
            dietaryPreference: dietaryPreference,
            customDietDescription: dietaryPreference == .custom && !diet.isEmpty ? diet : nil,
            allergies: allergies,
            otherRestrictions: restriction.isEmpty ? [] : [restriction],
            focusAreas: focusAreas,
            nutritionTargets: NutritionTargetCalculator.targets(for: input),
            waterTargetMilliliters: NutritionTargetCalculator.waterTargetMilliliters(weightKilograms: weightKilograms),
            createdAt: now,
            updatedAt: now,
            prefersAppleHealth: prefersAppleHealth
        )
    }
}
