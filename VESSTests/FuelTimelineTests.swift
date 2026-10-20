import Foundation
import Testing
@testable import VESS

/// The demo day (DATA.md) through the day: Fuel and the Today strip values at
/// fixed times, counting only what was logged by then. Records the rule's
/// behaviour: Fuel never falls while the day is under target.
@Suite("Fuel through the demo day")
struct FuelTimelineTests {
    struct Row {
        let time: String
        let fuel: Int?
        let energy: Int
        let protein: Int
        let water: Int
    }

    private func row(_ hour: Int, _ minute: Int, withDinner: Bool = false) throws -> Row {
        let calendar = TestClock.utc
        let day = try TestClock.date(2026, 10, 6, 18, 40)
        let now = try TestClock.date(2026, 10, 6, hour, minute)
        let data = MockData(now: day, calendar: calendar)
        let food = (data.foodLog + (withDinner ? data.fullDayExtras : [])).filter { $0.loggedAt <= now }
        let drinks = data.hydrationLog.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) && $0.loggedAt <= now }
        let summary = DaySummary(
            entries: food, hydrationLogs: drinks,
            targets: data.profile.nutritionTargets, waterTargetMilliliters: data.profile.waterTargetMilliliters,
            day: now, now: now, calendar: calendar
        )
        let regularity = MealRegularity.dayProgress(today: food, history: data.foodHistory, calendar: calendar)
        let fuel = FuelScore(summary: summary, hasLoggedFood: !food.isEmpty, regularity: regularity)
        func percent(_ value: Double, _ target: Double) -> Int { Int((value / target * 100).rounded()) }
        return Row(
            time: String(format: "%02d:%02d%@", hour, minute, withDinner ? " + dinner" : ""),
            fuel: fuel?.value,
            energy: percent(summary.consumed.calories, summary.targets.calories),
            protein: percent(summary.consumed.proteinGrams, summary.targets.proteinGrams),
            water: percent(summary.hydration.consumedMilliliters, summary.hydration.targetMilliliters)
        )
    }

    @Test("Fuel and strip values at fixed times")
    func timeline() throws {
        let rows = [
            try row(8, 0), try row(10, 30), try row(12, 50), try row(15, 0),
            try row(18, 40), try row(22, 0), try row(22, 0, withDinner: true),
        ]
        // Fuel, then the strip: energy, protein and water as % of the full target.
        #expect(rows.map(\.fuel) == [21, 26, 54, 57, 76, 76, 93])
        // Under target, logging only ever raises it.
        let fuel = rows.compactMap(\.fuel)
        #expect(zip(fuel, fuel.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(rows.map(\.energy) == [28, 28, 65, 65, 77, 77, 101])
        #expect(rows.map(\.protein) == [26, 26, 61, 61, 77, 77, 105])
        #expect(rows.map(\.water) == [0, 23, 23, 38, 73, 73, 73])
    }
}
