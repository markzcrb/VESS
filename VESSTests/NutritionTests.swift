import Foundation
import Testing
@testable import VESS

@Suite("Nutrition calculations")
struct NutritionTests {
    @Test("Logging a quantity scales the food's per-serving nutrition")
    func logScalesNutrition() throws {
        let data = MockData(now: try TestClock.date(2026, 3, 10, 18), calendar: TestClock.utc)
        let salmon = try #require(data.foods.first { $0.name == "Salmon poke" })

        // 324 kcal and 31 g protein per 155 g serving; twice the serving doubles both.
        let entry = FoodLogEntry(userID: data.profile.id, food: salmon, quantity: 310, mealType: .lunch, loggedAt: .now)

        #expect(entry.nutrition.calories.isApproximately(648))
        #expect(entry.nutrition.proteinGrams.isApproximately(62))
        #expect(entry.servingUnit == .gram)
        #expect(entry.foodName == salmon.name)
    }

    @Test("A food with no serving size yields zero instead of infinity")
    func zeroServingSizeIsSafe() throws {
        let data = MockData(now: .now, calendar: TestClock.utc)
        var food = try #require(data.foods.first)
        food.servingSize = 0

        #expect(food.nutrition(forQuantity: 100) == .zero)
    }

    @Test("Optional nutrients stay unknown unless one side knows them")
    func optionalNutrientsSum() {
        let unknown = NutritionFacts(calories: 100, proteinGrams: 1, carbohydrateGrams: 2, fatGrams: 3)
        var withFiber = unknown
        withFiber.fiberGrams = 4

        #expect((unknown + unknown).fiberGrams == nil)
        #expect((unknown + withFiber).fiberGrams == 4)
        #expect((unknown + withFiber).calories == 200)
    }

    @Test("Additional nutrients merge by identifier")
    func additionalNutrientsMerge() {
        var lhs = NutritionFacts.zero
        lhs.additional = [.vitaminD: 2, .iron: 1]
        var rhs = NutritionFacts.zero
        rhs.additional = [.vitaminD: 3]

        let sum = lhs + rhs
        #expect(sum.additional[.vitaminD] == 5)
        #expect(sum.additional[.iron] == 1)
    }

    @Test("Daily totals add up every logged entry")
    func dailyTotals() throws {
        let data = MockData(now: try TestClock.date(2026, 3, 10, 18), calendar: TestClock.utc)
        let totals = data.foodLog.totalNutrition

        // Breakfast 674 + lunch 894 + snack 272 (DATA.md)
        #expect(totals.calories.isApproximately(1840))
        #expect(totals.proteinGrams.isApproximately(108))
        #expect(totals.carbohydrateGrams.isApproximately(196))
        #expect(totals.fatGrams.isApproximately(58))
        // 7.5 + 3.5 + 4 + 4 + 0.6 + 1.4; yogurt and salmon don't report fibre.
        #expect(totals.fiberGrams?.isApproximately(21) == true)
    }

    @Test("Entries are grouped by meal")
    func entriesByMeal() throws {
        let data = MockData(now: try TestClock.date(2026, 3, 10, 18), calendar: TestClock.utc)

        #expect(data.foodLog.entries(for: .breakfast).count == 3)
        #expect(data.foodLog.entries(for: .lunch).count == 3)
        #expect(data.foodLog.entries(for: .snack).count == 3)
        #expect(data.foodLog.entries(for: .dinner).isEmpty)
    }
}
