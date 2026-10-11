import Foundation
import Testing
@testable import MyApp

@Suite("Day summary and Day Word")
struct DaySummaryTests {
    private let targets = NutritionTargets(calories: 2000, proteinGrams: 100, carbohydrateGrams: 250, fatGrams: 70)
    private let userID = UUID()

    private func entry(kcal: Double, protein: Double = 0, meal: MealType = .lunch, at date: Date) -> FoodLogEntry {
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

    private func summary(_ entries: [FoodLogEntry], water logs: [HydrationLog] = [], now: Date, day: Date? = nil) -> DaySummary {
        DaySummary(
            entries: entries, hydrationLogs: logs, targets: targets, waterTargetMilliliters: 2000,
            day: day ?? now, now: now, calendar: TestClock.utc
        )
    }

    @Test("Nothing logged is a fresh start")
    func freshStart() throws {
        let now = try TestClock.date(2026, 3, 10, 14)
        #expect(summary([], now: now).dayWord == .freshStart)
    }

    @Test("Expected pace runs from 07:00 to 21:00", arguments: [(6, 0.0), (7, 0.0), (14, 0.5), (21, 1.0), (23, 1.0)])
    func pace(hour: Int, expected: Double) throws {
        let now = try TestClock.date(2026, 3, 10, hour)
        #expect(DaySummary.expectedPace(day: now, now: now, calendar: TestClock.utc) == expected)
    }

    @Test("Past days are judged against the full day")
    func pastDay() throws {
        let now = try TestClock.date(2026, 3, 10, 9)
        let yesterday = try TestClock.date(2026, 3, 9, 12)
        let result = summary([entry(kcal: 1000, at: yesterday)], now: now, day: yesterday)

        #expect(result.expectedPace == 1)
        #expect(result.dayWord == .lightSoFar)
    }

    @Test("Eating in step with the time of day is on track")
    func onTrack() throws {
        // At 14:00 the expected pace is 50%; 900 of 2,000 kcal is 45%, above 75% of pace.
        let now = try TestClock.date(2026, 3, 10, 14)
        let result = summary([entry(kcal: 900, protein: 45, at: now)], water: [water(900, at: now)], now: now)

        #expect(result.dayWord == .onTrack)
        #expect(!result.isProteinBehind)
        #expect(!result.isWaterBehind)
        #expect(result.caloriesRemaining == 1100)
    }

    @Test("Well under pace is light so far, and lagging measures are flagged")
    func lightSoFar() throws {
        let now = try TestClock.date(2026, 3, 10, 18)
        let result = summary([entry(kcal: 600, protein: 10, at: now)], water: [water(300, at: now)], now: now)

        #expect(result.dayWord == .lightSoFar)
        #expect(result.isProteinBehind)
        #expect(result.isWaterBehind)
    }

    @Test("Early in the day nothing counts as behind")
    func earlyMorning() throws {
        let now = try TestClock.date(2026, 3, 10, 8)
        let result = summary([entry(kcal: 50, at: now)], now: now)

        #expect(!result.isProteinBehind)
        #expect(!result.isWaterBehind)
    }

    @Test("Reaching 95% of the calorie target is a full day, including above target")
    func fullDay() throws {
        let now = try TestClock.date(2026, 3, 10, 20)
        #expect(summary([entry(kcal: 1900, at: now)], now: now).dayWord == .fullDay)

        let above = summary([entry(kcal: 2425, at: now)], now: now)
        #expect(above.dayWord == .fullDay)
        #expect(above.caloriesRemaining == -425)
    }

    @Test("Only the summarized day's entries count")
    func excludesOtherDays() throws {
        let now = try TestClock.date(2026, 3, 10, 12)
        let yesterday = try TestClock.date(2026, 3, 9, 12)
        let result = summary([entry(kcal: 500, at: now), entry(kcal: 2000, at: yesterday)], now: now)

        #expect(result.consumed.calories == 500)
    }
}

@Suite("Meal suggestions")
struct MealSuggestionTests {
    @Test("Suggests the first unlogged main meal whose time hasn't passed")
    func nextMeal() throws {
        let morning = try TestClock.date(2026, 3, 10, 9)
        let afternoon = try TestClock.date(2026, 3, 10, 17)
        let lateNight = try TestClock.date(2026, 3, 10, 23, 30)

        #expect(MealType.nextSuggestion(logged: [], now: morning, calendar: TestClock.utc) == .breakfast)
        #expect(MealType.nextSuggestion(logged: [.breakfast], now: morning, calendar: TestClock.utc) == .lunch)
        // Breakfast and lunch windows have passed; snacks are never suggested.
        #expect(MealType.nextSuggestion(logged: [.snack], now: afternoon, calendar: TestClock.utc) == .dinner)
        #expect(MealType.nextSuggestion(logged: [.dinner], now: lateNight, calendar: TestClock.utc) == nil)
    }

    @Test("Usual meal time is the rounded median over at least three days")
    func usualTime() throws {
        let userID = UUID()
        func dinner(day: Int, hour: Int, minute: Int) throws -> FoodLogEntry {
            FoodLogEntry(
                id: UUID(), userID: userID, foodID: nil, foodName: "Dinner", mealType: .dinner,
                quantity: 1, servingUnit: .serving, nutrition: .zero,
                loggedAt: try TestClock.date(2026, 3, day, hour, minute)
            )
        }
        let history = [
            try dinner(day: 1, hour: 19, minute: 10),
            try dinner(day: 2, hour: 19, minute: 40),
            try dinner(day: 2, hour: 20, minute: 30), // Second item that day; ignored.
            try dinner(day: 3, hour: 19, minute: 25),
        ]

        let usual = history.usualTime(for: .dinner, calendar: TestClock.utc)
        #expect(usual?.hour == 19)
        #expect(usual?.minute == 30)

        #expect(history.prefix(2).usualTime(for: .dinner, calendar: TestClock.utc) == nil)
        #expect(history.usualTime(for: .lunch, calendar: TestClock.utc) == nil)
    }
}
