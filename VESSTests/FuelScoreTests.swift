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

    private func score(kcal: Double, protein: Double, waterMl: Double, at now: Date, regularity: Double? = nil) -> FuelScore? {
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

    @Test("Scored against full-day targets, whatever the time")
    func fullDayTargets() throws {
        // Half of every target scores half, at 09:00 and at 22:00 alike.
        let morning = try #require(score(kcal: 1000, protein: 50, waterMl: 1000, at: try TestClock.date(2026, 10, 6, 9), regularity: 0.5))
        let evening = try #require(score(kcal: 1000, protein: 50, waterMl: 1000, at: try TestClock.date(2026, 10, 6, 22), regularity: 0.5))
        #expect(morning == evening)
        #expect(morning.components.energy.isApproximately(0.5))
        #expect(morning.value == 50)
    }

    @Test("Energy rises to full marks at 100 %, holds to 105 %, then declines gently")
    func energyCurve() {
        #expect(FuelScore.energyScore(0.5).isApproximately(0.5))
        #expect(FuelScore.energyScore(0.9).isApproximately(0.9))
        #expect(FuelScore.energyScore(1.0) == 1)
        #expect(FuelScore.energyScore(1.05) == 1)
        #expect(FuelScore.energyScore(1.25).isApproximately(0.8))
        #expect(FuelScore.energyScore(1.55).isApproximately(0.5))
        #expect(FuelScore.energyScore(2.05) == 0)
        #expect(FuelScore.energyScore(3.0) == 0)
    }

    @Test("Logging more never lowers the score until energy passes 105 %")
    func onlyRises() throws {
        let now = try TestClock.date(2026, 10, 6, 20)
        var previous = -1
        for kcal in stride(from: 100.0, through: 2100, by: 100) {
            let fuel = try #require(score(kcal: kcal, protein: kcal / 20, waterMl: kcal, at: now, regularity: 1))
            #expect(fuel.value >= previous, "\(kcal) kcal scored \(fuel.value), below \(previous)")
            previous = fuel.value
        }
        // Past 105 %, energy is the only part that can fall.
        let over = try #require(score(kcal: 2500, protein: 125, waterMl: 2500, at: now, regularity: 1))
        #expect(over.value < previous)
    }

    @Test("Weights are 40 / 30 / 20 / 10")
    func weights() throws {
        let now = try TestClock.date(2026, 10, 6, 22)
        #expect(try #require(score(kcal: 2000, protein: 0, waterMl: 0, at: now, regularity: 0)).value == 40)
        #expect(try #require(score(kcal: 2000, protein: 100, waterMl: 0, at: now, regularity: 0)).value == 70)
        #expect(try #require(score(kcal: 2000, protein: 100, waterMl: 2000, at: now, regularity: 0)).value == 90)
    }

    @Test("Without regularity history its 10 % is left out, not guessed")
    func regularityMissing() throws {
        let fuel = try #require(score(kcal: 2000, protein: 100, waterMl: 0, at: try TestClock.date(2026, 10, 6, 22)))
        #expect(fuel.components.regularity == nil)
        #expect(fuel.value == Int((70.0 / 90 * 100).rounded()))
    }

    @Test("Eating twice the target leaves almost no energy marks, never below zero")
    func overTarget() throws {
        let fuel = try #require(score(kcal: 4200, protein: 100, waterMl: 2000, at: try TestClock.date(2026, 10, 6, 22), regularity: 1))
        #expect(fuel.components.energy == 0)
        #expect(fuel.value == 60)
    }
}

@Suite("Fuel score on the DATA.md day")
struct FuelScoreSampleDayTests {
    @Test("Tuesday at 18:40, dinner not yet logged, scores 76")
    func sampleDay() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let data = MockData(now: now, calendar: TestClock.utc)
        let summary = DaySummary(
            entries: data.foodLog, hydrationLogs: data.hydrationLog,
            targets: data.profile.nutritionTargets, waterTargetMilliliters: data.profile.waterTargetMilliliters,
            day: now, now: now, calendar: TestClock.utc
        )
        let regularity = MealRegularity.dayProgress(today: data.foodLog, history: data.foodHistory, calendar: TestClock.utc)
        let fuel = try #require(FuelScore(summary: summary, hasLoggedFood: true, regularity: regularity))

        // Energy 1,840 of 2,400 from food, plus the day's drinks (their kcal
        // count since 2026-10-23: the green tea's 3); protein 108 of 140 g;
        // water 1.6 of 2.2 L; three of four meal slots logged on time.
        let drinkKcal = data.hydrationLog.filter { TestClock.utc.isDate($0.loggedAt, inSameDayAs: now) }.reduce(0) { $0 + $1.calories }
        #expect(drinkKcal < 10, "The sample drinks are almost kcal-free")
        #expect(fuel.components.energy.isApproximately((1840.0 + drinkKcal) / 2400))
        #expect(fuel.components.protein.isApproximately(108.0 / 140))
        #expect(fuel.components.hydration.isApproximately(1600.0 / 2200))
        #expect(fuel.components.regularity?.isApproximately(0.74, tolerance: 0.005) == true)
        #expect(fuel.value == 76)
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

    @Test("Day progress sums each slot's score over every slot with a usual time")
    func dayProgress() throws {
        let history = try history(.breakfast, hour: 8, minute: 0) + history(.lunch, hour: 12, minute: 0)
        let breakfast = [entry(.breakfast, at: try TestClock.date(2026, 10, 6, 8, 0))]
        #expect(MealRegularity.dayProgress(today: breakfast, history: history, calendar: TestClock.utc)?.isApproximately(0.5) == true)
        // A late lunch still adds (0.5 of its share), never subtracts.
        let both = breakfast + [entry(.lunch, at: try TestClock.date(2026, 10, 6, 13, 0))]
        #expect(MealRegularity.dayProgress(today: both, history: history, calendar: TestClock.utc)?.isApproximately(0.75) == true)
        #expect(MealRegularity.dayProgress(today: [], history: history, calendar: TestClock.utc) == 0)
        #expect(MealRegularity.dayProgress(today: breakfast, history: [], calendar: TestClock.utc) == nil)
    }
}
