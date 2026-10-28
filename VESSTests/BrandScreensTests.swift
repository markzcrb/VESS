import Foundation
import Testing
@testable import VESS

@Suite("B03 targets and B04 once per subscription")
struct BrandScreensTests {
    private func profile(calories: Double = 2400, protein: Double = 150, water: Double = 2500,
                         steps: Int? = nil, sleep: Int? = nil, name: String = "Mark Gerasimov") -> UserProfile {
        UserProfile(id: UUID(), name: name, dateOfBirth: nil, sex: .male, heightCentimeters: 178, weightKilograms: 68,
                    goalWeightKilograms: nil, goal: .buildMuscle, activityLevel: .moderate, dietaryPreference: .everything,
                    customDietDescription: nil, allergies: [], otherRestrictions: [], focusAreas: [],
                    nutritionTargets: NutritionTargets(calories: calories, proteinGrams: protein, carbohydrateGrams: 250, fatGrams: 70),
                    waterTargetMilliliters: water, createdAt: .now, updatedAt: .now, stepsTarget: steps, sleepTargetMinutes: sleep)
    }

    @Test("Energy, protein, water, steps and sleep, in that order; steps and sleep use their defaults")
    func rows() {
        #expect(AllSetTargets.rows(for: profile()) == [.energy(kcal: 2400), .protein(grams: 150), .water(milliliters: 2500),
                                                        .steps(8_000), .sleep(minutes: 480)])
    }

    @Test("A target that isn't set is left out, not shown as 0")
    func unset() {
        #expect(AllSetTargets.rows(for: profile(protein: 0, water: 0, steps: 0)) == [.energy(kcal: 2400), .sleep(minutes: 480)])
    }

    @Test("The first name, or none")
    func firstName() {
        #expect(AllSetTargets.firstName(profile().name) == "Mark")
        #expect(AllSetTargets.firstName("  ") == nil)
    }

    @Test("B04 claims each original transaction once")
    func ledger() throws {
        let defaults = try #require(UserDefaults(suiteName: "BrandScreensTests.\(UUID())"))
        let ledger = PlusWelcomeLedger(defaults: defaults)
        #expect(ledger.claim(42))
        #expect(!ledger.claim(42), "Not again for the same subscription")
        #expect(ledger.claim(43), "A new subscription is welcomed")
    }

    @Test("UMEVA+ gives more of every AI feature than free")
    func limits() {
        let free = UMEVAPlusLimits.free, plus = UMEVAPlusLimits.plus
        #expect(plus.coachQuestions > free.coachQuestions && plus.photoEstimates > free.photoEstimates && plus.chefRecipes > free.chefRecipes)
    }
}
