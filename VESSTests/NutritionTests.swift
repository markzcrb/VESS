import Foundation
import Testing
@testable import MyApp

@Suite("Nutrition calculations")
struct NutritionTests {
    @Test("Logging a quantity scales the food's per-serving nutrition")
    func logScalesNutrition() throws {
        let data = MockData(now: try TestClock.date(2026, 3, 10, 18), calendar: TestClock.utc)
        let chicken = try #require(data.foods.first { $0.name == "Chicken breast, grilled" })

        let entry = FoodLogEntry(userID: data.profile.id, food: chicken, quantity: 150, mealType: .lunch, loggedAt: .now)

        #expect(entry.nutrition.calories.isApproximately(247.5))
        #expect(entry.nutrition.proteinGrams.isApproximately(46.5))
        #expect(entry.servingUnit == .gram)
        #expect(entry.foodName == chicken.name)
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

        // 300 + 124 + 32 (breakfast) + 247.5 + 260 + 80 (lunch) + 164 + 105 (snack)
        #expect(totals.calories.isApproximately(1312.5))
        // 10.6 + 17 + 0.7 + 46.5 + 5.4 + 1 + 6 + 1.3
        #expect(totals.proteinGrams.isApproximately(88.5))
    }

    @Test("Entries are grouped by meal")
    func entriesByMeal() throws {
        let data = MockData(now: try TestClock.date(2026, 3, 10, 18), calendar: TestClock.utc)

        #expect(data.foodLog.entries(for: .breakfast).count == 3)
        #expect(data.foodLog.entries(for: .lunch).count == 3)
        #expect(data.foodLog.entries(for: .snack).count == 2)
        #expect(data.foodLog.entries(for: .dinner).isEmpty)
    }
}
