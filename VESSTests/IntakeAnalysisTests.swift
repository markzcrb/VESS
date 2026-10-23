import Foundation
import Testing
@testable import VESS

@Suite("Intake analysis")
struct IntakeAnalysisTests {
    private let userID = UUID()

    private func entry(_ kcal: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0, at date: Date) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID(), userID: userID, foodID: nil, foodName: "Food", mealType: .lunch,
            quantity: 1, servingUnit: .serving,
            nutrition: NutritionFacts(calories: kcal, proteinGrams: protein, carbohydrateGrams: carbs, fatGrams: fat),
            loggedAt: date
        )
    }

    @Test("Before noon is the share of energy logged before 12:00")
    func beforeNoon() throws {
        let entries = [
            entry(300, at: try TestClock.date(2026, 10, 6, 7, 45)),
            entry(100, at: try TestClock.date(2026, 10, 6, 11, 59)),
            entry(600, at: try TestClock.date(2026, 10, 6, 12, 0)),
        ]
        #expect(IntakeAnalysis.beforeNoonShare(entries, calendar: TestClock.utc)?.isApproximately(0.4) == true)
        #expect(IntakeAnalysis.beforeNoonShare([], calendar: TestClock.utc) == nil)
    }

    @Test("The running total steps up at each logging time")
    func cumulative() throws {
        let entries = [
            entry(200, at: try TestClock.date(2026, 10, 6, 12, 30)),
            entry(500, at: try TestClock.date(2026, 10, 6, 7, 45)),
            entry(100, at: try TestClock.date(2026, 10, 6, 12, 30)),
        ]
        let points = IntakeAnalysis.cumulative(entries, calendar: TestClock.utc)
        #expect(points == [.init(minute: 465, calories: 500), .init(minute: 750, calories: 800)])
    }

    @Test("Daily totals cover consecutive days, oldest first, and average only logged days")
    func dailyTotals() throws {
        let entries = [
            entry(2000, at: try TestClock.date(2026, 10, 4, 12)),
            entry(1000, at: try TestClock.date(2026, 10, 6, 9)),
            entry(500, at: try TestClock.date(2026, 10, 6, 13)),
        ]
        let totals = IntakeAnalysis.dailyTotals(entries, endingOn: try TestClock.date(2026, 10, 6, 18), days: 3, calendar: TestClock.utc)
        #expect(totals.map(\.nutrition.calories) == [2000, 0, 1500])
        #expect(totals.map(\.hasEntries) == [true, false, true])
        #expect(IntakeAnalysis.average(totals, \.calories) == 1750)
        #expect(IntakeAnalysis.average([], \.calories) == nil)
    }

    @Test("Week average: only days with meals, never today, and at least three of them")
    func weekAverage() throws {
        let today = try TestClock.date(2026, 10, 9, 18)
        let entries = [
            entry(2000, at: try TestClock.date(2026, 10, 4, 12)),
            entry(1800, at: try TestClock.date(2026, 10, 6, 12)),
            entry(500, at: try TestClock.date(2026, 10, 9, 9)),     // today: left out
        ]
        // A day with only a drink isn't a day with meals.
        let drinkOnly = [IntakeAnalysis.EnergyItem(date: try TestClock.date(2026, 10, 7, 20), calories: 140)]
        let two = IntakeAnalysis.dailyTotals(entries, extra: drinkOnly, endingOn: today, days: 7, calendar: TestClock.utc)
        #expect(two.map(\.hasMeals) == [false, true, false, true, false, false, true])
        #expect(IntakeAnalysis.weekAverage(two, today: today, calendar: TestClock.utc) == .notEnough(days: 2))

        let three = IntakeAnalysis.dailyTotals(entries + [entry(2200, at: try TestClock.date(2026, 10, 8, 13))], extra: drinkOnly,
                                               endingOn: today, days: 7, calendar: TestClock.utc)
        #expect(IntakeAnalysis.weekAverage(three, today: today, calendar: TestClock.utc) == .average(calories: 2000, days: 3))
        #expect(IntakeAnalysis.weekAverage([], today: today, calendar: TestClock.utc) == .notEnough(days: 0))
    }

    @Test("Energy split uses 4 / 4 / 9 kcal per gram and sums to 1")
    func energySplit() throws {
        // 108 g protein (432), 196 g carbs (784), 58 g fat (522): 1,738 kcal.
        let split = try #require(IntakeAnalysis.energySplit(proteinGrams: 108, carbGrams: 196, fatGrams: 58))
        #expect(split.protein.isApproximately(0.2486))
        #expect(split.carbs.isApproximately(0.4511))
        #expect(split.fat.isApproximately(0.3003))
        #expect((split.protein + split.carbs + split.fat).isApproximately(1))
        #expect(IntakeAnalysis.energySplit(proteinGrams: 0, carbGrams: 0, fatGrams: 0) == nil)
    }

    @Test("Status levels: energy is never low for being ahead; regularity uses fixed bands")
    func levels() {
        #expect(StatusLevel.energy(ratio: 0.95) == .optimal)
        #expect(StatusLevel.energy(ratio: 1.05) == .optimal)
        #expect(StatusLevel.energy(ratio: 0.72) == .sufficient)   // 0.8 of full marks
        #expect(StatusLevel.energy(ratio: 0.50) == .low)
        #expect(StatusLevel.energy(ratio: 1.40) == .sufficient)   // ahead of the clock, not low
        #expect(StatusLevel.regularity(0.9) == .optimal)
        #expect(StatusLevel.regularity(0.7) == .sufficient)
        #expect(StatusLevel.regularity(0.4) == .low)
    }
}
