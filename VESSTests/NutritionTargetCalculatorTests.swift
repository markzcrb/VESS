import Foundation
import Testing
@testable import VESS

@Suite("Nutrition targets")
struct NutritionTargetCalculatorTests {
    private let alex = NutritionTargetCalculator.Input(
        sex: .male,
        ageYears: 29,
        heightCentimeters: 178,
        weightKilograms: 68,
        activityLevel: .moderate,
        goal: .buildMuscle,
        dietaryPreference: .highProtein
    )

    @Test("Resting energy follows Mifflin-St Jeor")
    func restingEnergy() {
        // 10 × 68 + 6.25 × 178 − 5 × 29 + 5
        #expect(NutritionTargetCalculator.restingEnergy(for: alex) == 1652.5)

        var female = alex
        female.sex = .female
        #expect(NutritionTargetCalculator.restingEnergy(for: female) == 1486.5)

        var unspecified = alex
        unspecified.sex = .notSpecified
        #expect(NutritionTargetCalculator.restingEnergy(for: unspecified) == 1569.5)
    }

    @Test("Targets combine activity, goal, protein per kg and fat share")
    func alexTargets() {
        let targets = NutritionTargetCalculator.targets(for: alex)

        // 1652.5 × 1.55 × 1.10 = 2817.5 → nearest 50
        #expect(targets.calories == 2800)
        // 68 kg × 1.8 g = 122.4 → nearest 5
        #expect(targets.proteinGrams == 120)
        // 2800 × 28% ÷ 9 = 87.1 → nearest 5
        #expect(targets.fatGrams == 85)
        // (2800 − 120 × 4 − 85 × 9) ÷ 4 = 388.75 → nearest 5
        #expect(targets.carbohydrateGrams == 390)
    }

    @Test("Macros never exceed the calorie target")
    func macrosAddUp() {
        for goal in WellnessGoal.allCases {
            for diet in DietaryPreference.allCases {
                var input = alex
                input.goal = goal
                input.dietaryPreference = diet
                let t = NutritionTargetCalculator.targets(for: input)
                let macroEnergy = t.proteinGrams * 4 + t.carbohydrateGrams * 4 + t.fatGrams * 9
                // Rounding to 5 g can shift energy by a few dozen kcal at most.
                #expect(abs(macroEnergy - t.calories) <= 40, "\(goal) \(diet)")
            }
        }
    }

    @Test("Weight loss never suggests fewer than 1,200 kcal")
    func calorieFloor() {
        let small = NutritionTargetCalculator.Input(
            sex: .female, ageYears: 70, heightCentimeters: 150, weightKilograms: 42,
            activityLevel: .sedentary, goal: .loseWeight, dietaryPreference: .everything
        )
        #expect(NutritionTargetCalculator.targets(for: small).calories == NutritionTargetCalculator.minimumCalories)
    }

    @Test("Low carb shifts energy from carbohydrates to fat")
    func lowCarb() {
        var lowCarb = alex
        lowCarb.dietaryPreference = .lowCarb
        let standard = NutritionTargetCalculator.targets(for: alex)
        let reduced = NutritionTargetCalculator.targets(for: lowCarb)

        #expect(reduced.fatGrams > standard.fatGrams)
        #expect(reduced.carbohydrateGrams < standard.carbohydrateGrams)
    }

    @Test("Water target is 33 ml per kg, clamped to 1.5–4 L", arguments: [(68.0, 2200.0), (30.0, 1500.0), (150.0, 4000.0)])
    func water(weight: Double, expected: Double) {
        #expect(NutritionTargetCalculator.waterTargetMilliliters(weightKilograms: weight) == expected)
    }
}
