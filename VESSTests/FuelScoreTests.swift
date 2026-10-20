import Foundation
import Testing
@testable import VESS

@Suite("Fuel score")
struct FuelScoreTests {
    private let targets = NutritionTargets(calories: 2000, proteinGrams: 100, carbohydrateGrams: 250, fatGrams: 70)
    private let userID = UUID()

    private func entry(kcal: Double, protein: Double, meal: MealType = .lunch, at date: Date) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID(), userID: userID, foodID: nil, foodName: "Food", mealType: meal,
            quantity: 1, servingUnit: .serving,
            nutrition: NutritionFacts(calories: kcal, proteinGrams: protein, carbohydrateGrams: 0, fatGrams: 0),
            loggedAt: date
        )
    }

    private func water(_ ml: Double, at date: Date) -> HydrationLog {
        DrinkPreset.water.drink(name: "Water").log(userID: userID, volumeMilliliters: ml, at: date)
    }

    private func score(
        kcal: Double, protein: Double, waterMl: Double, at now: Date, regularity: Double? = nil
    ) -> FuelScore? {
        let entries = kcal > 0 || protein > 0 ? [entry(kcal: kcal, protein: protein, at: now)] : []
        let summary = DaySummary(
            entries: entries, hydrationLogs: waterMl > 0 ? [water(waterMl, at: now)] : [],
            targets: targets, waterTargetMilliliters: 2000, day: now, now: now, calendar: TestClock.utc
        )
        return FuelScore(summary: summary, hasLoggedFood: !entries.isEmpty, regularity: regularity)
    }

    @Test("No score before the first food is logged")
    func noScoreBeforeFirstLog() throws {
        #expect(score(kcal: 0, protein: 0, waterMl: 500, at: try TestClock.date(2026, 10, 6, 10)) == nil)
    }

    @Test("A complete day on every target scores 100")
    func fullMarks() throws {
        let fuel = try #require(score(kcal: 2000, protein: 100, waterMl: 2000, at: try TestClock.date(2026, 10, 6, 22), regularity: 1))
        #expect(fuel.value == 100)
    }

    @Test("Targets are prorated: half the day with half the targets scores full marks")
    func prorated() throws {
        // 14:00 is half of the 07:00–21:00 window.
        let fuel = try #require(score(kcal: 1000, protein: 50, waterMl: 1000, at: try TestClock.date(2026, 10, 6, 14)))
        #expect(fuel.components.energy == 1)
        #expect(fuel.components.protein.isApproximately(1))
        #expect(fuel.components.hydration.isApproximately(1))
        #expect(fuel.value == 100)
    }

    @Test("Energy scores full marks from 90 to 105 % and falls to zero at 150 %")
    func energyCurve() {
        #expect(FuelScore.energyScore(0.45).isApproximately(0.5))
        #expect(FuelScore.energyScore(0.90) == 1)
        #expect(FuelScore.energyScore(1.05) == 1)
        #expect(FuelScore.energyScore(1.275).isApproximately(0.5))
        #expect(FuelScore.energyScore(1.50) == 0)
        #expect(FuelScore.energyScore(2.0) == 0)
    }

    @Test("Weights are 40 / 30 / 20 / 10")
    func weights() throws {
        // Energy perfect, nothing else: 40 of 100.
        let energyOnly = try #require(score(kcal: 2000, protein: 0, waterMl: 0, at: try TestClock.date(2026, 10, 6, 22), regularity: 0))
        #expect(energyOnly.value == 40)
        // Energy and protein perfect: 70.
        let energyProtein = try #require(score(kcal: 2000, protein: 100, waterMl: 0, at: try TestClock.date(2026, 10, 6, 22), regularity: 0))
        #expect(energyProtein.value == 70)
        // Plus hydration: 90. Plus regularity: 100.
        let withoutRegularity = try #require(score(kcal: 2000, protein: 100, waterMl: 2000, at: try TestClock.date(2026, 10, 6, 22), regularity: 0))
        #expect(withoutRegularity.value == 90)
    }

    @Test("Without regularity history its 10 % is left out, not guessed")
    func regularityMissing() throws {
        // Energy and protein perfect, no water: 70 of the 90 available weight.
        let fuel = try #require(score(kcal: 2000, protein: 100, waterMl: 0, at: try TestClock.date(2026, 10, 6, 22)))
        #expect(fuel.components.regularity == nil)
        #expect(fuel.value == Int((70.0 / 90 * 100).rounded()))
    }

    @Test("An early breakfast is judged against at least a quarter of the targets")
    func minimumPace() throws {
        // 07:30 is under 5 % of the day; a 500 kcal breakfast is 100 % of a quarter.
        let fuel = try #require(score(kcal: 500, protein: 25, waterMl: 500, at: try TestClock.date(2026, 10, 6, 7, 30)))
        #expect(fuel.components.energy == 1)
        #expect(fuel.value == 100)
    }

    @Test("Eating well above the prorated target lowers energy, never below zero")
    func overTarget() throws {
        let fuel = try #require(score(kcal: 4000, protein: 100, waterMl: 2000, at: try TestClock.date(2026, 10, 6, 22), regularity: 1))
        #expect(fuel.components.energy == 0)
        #expect(fuel.value == 60)
    }
}

@Suite("Meal regularity")
struct MealRegularityTests {
    private let userID = UUID()

    private func entry(_ meal: MealType, at date: Date) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID(), userID: userID, foodID: nil, foodName: "Food", mealType: meal,
            quantity: 1, servingUnit: .serving, nutrition: .zero, loggedAt: date
        )
    }

    private func history(_ meal: MealType, hour: Int, minute: Int, days: Int = 5) throws -> [FoodLogEntry] {
        try (1...days).map { offset in
            entry(meal, at: try TestClock.date(2026, 10, 6 - offset, hour, minute))
        }
    }

    @Test("Meals at their usual time score 1")
    func onTime() throws {
        let today = [entry(.breakfast, at: try TestClock.date(2026, 10, 6, 7, 45))]
        let score = MealRegularity.score(today: today, history: try history(.breakfast, hour: 7, minute: 45), calendar: TestClock.utc)
        #expect(score == 1)
    }

    @Test("An hour off the usual time scores 0.5; two hours or more scores 0")
    func deviation() throws {
        let history = try history(.lunch, hour: 12, minute: 30)
        let hourLate = [entry(.lunch, at: try TestClock.date(2026, 10, 6, 13, 30))]
        #expect(MealRegularity.score(today: hourLate, history: history, calendar: TestClock.utc)?.isApproximately(0.5) == true)
        let veryLate = [entry(.lunch, at: try TestClock.date(2026, 10, 6, 15, 30))]
        #expect(MealRegularity.score(today: veryLate, history: history, calendar: TestClock.utc) == 0)
    }

    @Test("Meals are averaged; meals without a usual time are skipped")
    func averaged() throws {
        let history = try history(.breakfast, hour: 8, minute: 0) + history(.lunch, hour: 12, minute: 0)
        let today = [
            entry(.breakfast, at: try TestClock.date(2026, 10, 6, 8, 0)),   // 1
            entry(.lunch, at: try TestClock.date(2026, 10, 6, 13, 0)),      // 0.5
            entry(.snack, at: try TestClock.date(2026, 10, 6, 16, 0)),      // no history
        ]
        #expect(MealRegularity.score(today: today, history: history, calendar: TestClock.utc)?.isApproximately(0.75) == true)
    }

    @Test("No usual times yet means no score")
    func noHistory() throws {
        let today = [entry(.dinner, at: try TestClock.date(2026, 10, 6, 19, 30))]
        #expect(MealRegularity.score(today: today, history: [], calendar: TestClock.utc) == nil)
    }
}
