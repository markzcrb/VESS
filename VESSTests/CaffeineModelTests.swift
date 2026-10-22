import Foundation
import Testing
@testable import VESS

@Suite("Caffeine")
struct CaffeineModelTests {
    private let userID = UUID()
    private let calendar = TestClock.utc

    private func drink(_ mg: Double, at date: Date) -> HydrationLog {
        HydrationLog(
            id: UUID(), userID: userID, drinkID: nil, drinkName: "Coffee", drinkType: .coffee,
            volumeMilliliters: 200, hydrationContributionPercent: 80,
            calories: 0, sugarGrams: 0, caffeineMilligrams: mg, loggedAt: date
        )
    }

    @Test("Caffeine halves every 5 hours")
    func halfLife() throws {
        let noon = try TestClock.date(2026, 10, 6, 12, 0)
        let logs = [drink(100, at: noon)]
        #expect(CaffeineModel.remaining(logs, at: noon) == 100)
        #expect(abs(CaffeineModel.remaining(logs, at: try TestClock.date(2026, 10, 6, 17, 0)) - 50) < 0.0001)
        #expect(abs(CaffeineModel.remaining(logs, at: try TestClock.date(2026, 10, 6, 22, 0)) - 25) < 0.0001)
    }

    @Test("Drinks add up; drinks after the moment don't count; last night's still do")
    func sums() throws {
        let logs = [
            drink(80, at: try TestClock.date(2026, 10, 5, 21, 0)),  // last night
            drink(100, at: try TestClock.date(2026, 10, 6, 9, 0)),
            drink(60, at: try TestClock.date(2026, 10, 6, 14, 0)),
        ]
        let at = try TestClock.date(2026, 10, 6, 14, 0)
        let expected = 80 * pow(0.5, 17.0 / 5) + 100 * pow(0.5, 1.0) + 60
        #expect(abs(CaffeineModel.remaining(logs, at: at) - expected) < 0.0001)
        let before = try TestClock.date(2026, 10, 6, 8, 0)
        #expect(abs(CaffeineModel.remaining(logs, at: before) - 80 * pow(0.5, 11.0 / 5)) < 0.0001, "Later drinks don't count yet")
    }

    @Test("The day's total counts only that day's drinks, against 400 mg")
    func totals() throws {
        let logs = [
            drink(80, at: try TestClock.date(2026, 10, 5, 21, 0)),
            drink(100, at: try TestClock.date(2026, 10, 6, 9, 0)),
            drink(320, at: try TestClock.date(2026, 10, 6, 14, 0)),
        ]
        let total = CaffeineModel.total(logs, on: try TestClock.date(2026, 10, 6, 12, 0), calendar: calendar)
        #expect(total == 420)
        #expect(CaffeineModel.dailyLimitMilligrams == 400)
        #expect(CaffeineModel.limitShare(of: total) == 1.05)
    }

    @Test("The curve steps up at each drink and decays between them")
    func curve() throws {
        let start = try TestClock.date(2026, 10, 6, 6, 0)
        let end = try TestClock.date(2026, 10, 6, 12, 0)
        let coffee = try TestClock.date(2026, 10, 6, 9, 5)
        let points = CaffeineModel.curve([drink(100, at: coffee)], from: start, to: end, step: 3600)

        #expect(points.first?.date == start && points.last?.date == end)
        #expect(points.map(\.date) == points.map(\.date).sorted())
        let before = try #require(points.first { $0.date == coffee.addingTimeInterval(-1) })
        let at = try #require(points.first { $0.date == coffee })
        #expect(before.milligrams == 0 && at.milligrams == 100)
        #expect((points.last?.milligrams ?? 0) < 100)
        #expect(CaffeineModel.curve([], from: end, to: start).isEmpty)
    }

    @Test("The evening estimate refers to 22:00 that day")
    func evening() throws {
        let day = try TestClock.date(2026, 10, 6, 18, 40)
        #expect(CaffeineModel.evening(of: day, calendar: calendar) == (try TestClock.date(2026, 10, 6, 22, 0)))
    }
}
