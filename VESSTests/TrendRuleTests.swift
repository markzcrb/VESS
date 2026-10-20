import Foundation
import Testing
@testable import VESS

@Suite("Trend versus prior 30 days")
struct TrendRuleTests {
    private func sample(_ value: Double, day offset: Int, _ hour: Int, _ minute: Int = 0) throws -> TrendRule.Sample {
        let base = try TestClock.date(2026, 10, 20, hour, minute)
        let date = try #require(TestClock.utc.date(byAdding: .day, value: offset, to: base))
        return TrendRule.Sample(date: date, value: value)
    }

    /// One sample at `hour` on each of `days` prior days.
    private func history(days: Int, value: Double = 100, hour: Int = 12) throws -> [TrendRule.Sample] {
        try (1...days).map { try sample(value, day: -$0, hour) }
    }

    private func now() throws -> Date { try TestClock.date(2026, 10, 20, 18, 40) }

    @Test("Fewer than 7 days of history gives no trend")
    func needsSevenDays() throws {
        let six = try history(days: 6) + [try sample(150, day: 0, 12)]
        #expect(TrendRule.trend(samples: six, now: try now(), calendar: TestClock.utc) == nil)
        let seven = try history(days: 7) + [try sample(150, day: 0, 12)]
        #expect(TrendRule.trend(samples: seven, now: try now(), calendar: TestClock.utc) == .up)
    }

    @Test("More than 10 % above is up, more than 10 % below is down, otherwise flat")
    func threshold() throws {
        let past = try history(days: 10)
        func trend(_ today: Double) throws -> Trend? {
            TrendRule.trend(samples: past + [try sample(today, day: 0, 12)], now: try now(), calendar: TestClock.utc)
        }
        #expect(try trend(111) == .up)
        #expect(try trend(110) == .flat)
        #expect(try trend(90) == .flat)
        #expect(try trend(89) == .down)
    }

    @Test("Prior days count only up to the same clock time")
    func sameClockTime() throws {
        // Each prior day: 100 at 12:00 and 900 at 20:00. At 18:40 only the 100 counts.
        let past = try history(days: 8) + (1...8).map { try sample(900, day: -$0, 20) }
        let samples = past + [try sample(100, day: 0, 12)]
        #expect(TrendRule.trend(samples: samples, now: try now(), calendar: TestClock.utc) == .flat)
    }

    @Test("A day logged only after this time still counts as history, with zero so far")
    func laterOnlyDaysCount() throws {
        // 7 days with 100 at 12:00 plus 3 days logged only at 20:00: the average so far is 70.
        let past = try history(days: 7) + (8...10).map { try sample(500, day: -$0, 20) }
        let samples = past + [try sample(70, day: 0, 12)]
        #expect(TrendRule.trend(samples: samples, now: try now(), calendar: TestClock.utc) == .flat)
    }

    @Test("Days older than 30 days and samples later today are ignored")
    func window() throws {
        let old = try (31...40).map { try sample(1000, day: -$0, 12) }
        let samples = old + (try history(days: 7)) + [try sample(100, day: 0, 12), try sample(1000, day: 0, 20)]
        #expect(TrendRule.trend(samples: samples, now: try now(), calendar: TestClock.utc) == .flat)
    }

    @Test("A zero average gives no trend")
    func zeroAverage() throws {
        let samples = try history(days: 8, value: 0) + [try sample(50, day: 0, 12)]
        #expect(TrendRule.trend(samples: samples, now: try now(), calendar: TestClock.utc) == nil)
    }
}
