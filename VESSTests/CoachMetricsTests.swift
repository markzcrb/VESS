import Foundation
import Testing
@testable import VESS

@Suite("Coach context: every metric")
struct CoachMetricsTests {
    private let calendar = TestClock.utc

    /// The demo day (Tue 6 Oct 2026, 18:40) with everything on.
    private func demo(health: Bool = true) throws -> (CoachContextInput, MockData) {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let data = MockData(now: now, calendar: calendar)
        let input = CoachContextInput(
            now: now, calendar: calendar, name: data.profile.name,
            targets: data.profile.nutritionTargets, waterTargetMilliliters: data.profile.waterTargetMilliliters,
            stepsTarget: data.profile.dailyStepsTarget,
            entries: data.foodLog + data.foodHistory, drinks: data.hydrationLog,
            hourlySteps: health ? data.health.hourlySteps : nil,
            habitsDone: ["Walk after lunch"], habitsOpen: ["Stretch"],
            workouts: data.workouts + (health ? data.health.workouts : []),
            supplementsTaken: ["Vitamin D"], supplementsDue: [], cycle: nil,
            preferences: data.profile.preferences, allergens: data.profile.allergies,
            health: health ? data.health : nil,
            sleepTargetMinutes: data.profile.dailySleepTargetMinutes,
            weightKilograms: data.profile.weightKilograms, weightSavedAt: data.profile.updatedAt,
            goalWeightKilograms: data.profile.goalWeightKilograms, bmi: 24.2,
            habitCompletion7d: 0.75,
            plannedMealsToday: data.plannedMeals,
            pantryUseSoon: ["Spinach", "Skyr"]
        )
        return (input, data)
    }

    @Test("Sleep, resting heart rate, HRV and stress come from Apple Health as precomputed values")
    func health() throws {
        let context = CoachContextBuilder.build(try demo().0)
        let sleep = try #require(context.sleep)
        #expect(sleep.lastNight?.asleepMin == 432 && sleep.lastNight?.bedtime == "23:48" && sleep.lastNight?.wake == "07:06")
        #expect(sleep.byNight.count == 7)
        #expect(context.restingHr?.today == 58)
        #expect(context.restingHr?.usualLow != nil && context.restingHr?.usualHigh != nil)
        #expect(context.hrv?.today == 47)
        #expect(context.stress?.today == "calm")
        #expect(context.activeEnergy?.today == 412)
        #expect(context.body?.weightKg == 78.4 && context.body?.bmi == 24.2)
    }

    @Test("Without Apple Health its metrics are absent, never 0")
    func noHealth() throws {
        let context = CoachContextBuilder.build(try demo(health: false).0)
        #expect(context.sleep == nil && context.restingHr == nil && context.hrv == nil && context.stress == nil && context.activeEnergy == nil)
        let json = String(decoding: CoachContextBuilder.json(context), as: UTF8.self)
        #expect(!json.contains("\"resting_hr\""))
    }

    @Test("Caffeine against the limit, drinks by type, carbs/fat/fiber/sugar with 7 days")
    func logMetrics() throws {
        let (input, data) = try demo()
        let context = CoachContextBuilder.build(input)
        let today = data.hydrationLog.filter { calendar.isDate($0.loggedAt, inSameDayAs: input.now) && $0.loggedAt <= input.now }
        #expect(context.caffeine?.todayMg == Int(today.reduce(0) { $0 + $1.caffeineMilligrams }.rounded()))
        #expect(context.caffeine?.limitMg == 400 && context.caffeine?.byDay.count == 7)
        #expect(context.drinksToday.map(\.count).reduce(0, +) == today.count)
        #expect(context.carbs?.byDay.count == 7 && context.fat?.today != nil)
        #expect(context.habitsCompletion7dPct == 75)
        #expect(context.pantryUseSoon == ["Spinach", "Skyr"])
    }

    @Test("A day without data is null in the series, not 0")
    func nulls() throws {
        var (input, _) = try demo()
        input.entries = []
        input.drinks = []
        let context = CoachContextBuilder.build(input)
        #expect(context.carbs?.byDay.allSatisfy { $0.value == nil } == true)
        #expect(context.fiber?.avgKnownDays == nil)
        let json = String(decoding: CoachContextBuilder.json(context), as: UTF8.self)
        #expect(json.contains("\"value\":null"))
    }

    @Test("The full demo day fits in 16 000 characters with its 30-day series")
    func demoFits() throws {
        let context = CoachContextBuilder.build(try demo().0)
        #expect(CoachContextBuilder.characters(context) <= CoachContextBuilder.maxCharacters)
        #expect(context.last30Days?.energy.count == 30)
    }

    @Test("Over the limit, the 30-day series go first; today's totals stay")
    func dropOrder() throws {
        var (input, _) = try demo()
        input.pantryUseSoon = (0..<300).map { "Pantry item with a fairly long name \($0)" }
        input.habitsDone = (0..<60).map { "A habit with a long name \($0)" }
        let context = CoachContextBuilder.build(input)
        #expect(CoachContextBuilder.characters(context) <= CoachContextBuilder.maxCharacters)
        #expect(context.last30Days == nil)
        #expect(context.sleep != nil && context.caffeine != nil)
    }
}
