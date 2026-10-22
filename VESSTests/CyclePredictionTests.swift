import Foundation
import Testing
@testable import VESS

@Suite("Cycle prediction")
struct CyclePredictionTests {
    private let calendar = TestClock.utc

    private func day(_ date: Date, _ flow: CycleFlow = .medium, symptoms: Set<CycleSymptom> = []) -> CycleDay {
        CycleDay(id: UUID(), day: calendar.startOfDay(for: date), flow: flow, symptoms: symptoms, note: nil)
    }

    /// `length` period days from `start`.
    private func period(_ start: Date, length: Int = 5) -> [CycleDay] {
        (0..<length).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { day($0) }
    }

    /// Periods whose cycles have these lengths, oldest first, the last
    /// period starting on `lastStart`.
    private func history(lengths: [Int], lastStart: Date) -> [CycleDay] {
        var starts = [lastStart]
        for length in lengths.reversed() {
            starts.insert(calendar.date(byAdding: .day, value: -length, to: starts[0]) ?? lastStart, at: 0)
        }
        return starts.flatMap { period($0) }
    }

    @Test("A period is a run of flow days; a day or two unlogged doesn't split it; spotting never counts")
    func periods() throws {
        let start = try TestClock.date(2026, 9, 1)
        let days = [
            day(start), day(try TestClock.date(2026, 9, 2)),
            day(try TestClock.date(2026, 9, 5)),                // two days not logged: same period
            day(try TestClock.date(2026, 9, 9)),                // three days without: a new one
            day(try TestClock.date(2026, 9, 20), .spotting),    // spotting alone: no period
            day(try TestClock.date(2026, 9, 24), .none, symptoms: [.cramps]),
        ]
        let periods = CyclePrediction.periods(days, upTo: try TestClock.date(2026, 9, 30), calendar: calendar)
        #expect(periods.count == 2)
        #expect(periods[0].start == calendar.startOfDay(for: start))
        #expect(periods[0].lengthDays == 5)
        #expect(periods[1].lengthDays == 1)
    }

    @Test("Days after today are ignored")
    func future() throws {
        let days = period(try TestClock.date(2026, 10, 1)) + period(try TestClock.date(2026, 10, 29))
        #expect(CyclePrediction.periods(days, upTo: try TestClock.date(2026, 10, 6), calendar: calendar).count == 1)
    }

    @Test("Fewer than two completed cycles: no estimate, but the cycle day is known")
    func needsTwoCycles() throws {
        let today = try TestClock.date(2026, 10, 6)
        let one = CyclePrediction.summary(period(try TestClock.date(2026, 10, 1)), today: today, calendar: calendar)
        #expect(one.cycleDay == 6)
        #expect(one.estimate == nil)
        #expect(one.completedCycles.isEmpty)

        let two = CyclePrediction.summary(history(lengths: [29], lastStart: try TestClock.date(2026, 10, 1)), today: today, calendar: calendar)
        #expect(two.completedCycles.count == 1)
        #expect(two.estimate == nil)

        let three = CyclePrediction.summary(history(lengths: [29, 29], lastStart: try TestClock.date(2026, 10, 1)), today: today, calendar: calendar)
        #expect(three.estimate?.cycleCount == 2)

        let none = CyclePrediction.summary([], today: today, calendar: calendar)
        #expect(none.cycleDay == nil)
        #expect(none.cycles.isEmpty)
    }

    @Test("The window runs from the shortest to the longest of the last six cycles; expected is the average")
    func window() throws {
        let lastStart = try TestClock.date(2026, 10, 1)
        // Oldest first: the two 40-day cycles are older than the last six.
        let summary = CyclePrediction.summary(
            history(lengths: [40, 40, 28, 30, 29, 31, 28, 29], lastStart: lastStart),
            today: try TestClock.date(2026, 10, 6),
            calendar: calendar
        )
        let estimate = try #require(summary.estimate)
        #expect(estimate.cycleCount == 6)
        #expect(estimate.averageDays == 29)          // 175 / 6 = 29.17
        #expect(estimate.shortestDays == 28)
        #expect(estimate.longestDays == 31)
        #expect(estimate.windowStart == calendar.startOfDay(for: try TestClock.date(2026, 10, 29)))
        #expect(estimate.windowEnd == calendar.startOfDay(for: try TestClock.date(2026, 11, 1)))
        #expect(estimate.expected == calendar.startOfDay(for: try TestClock.date(2026, 10, 30)))
        #expect(summary.daysUntilExpected == 24)
        #expect(summary.cycleDay == 6)
        #expect(!estimate.isLessCertain)
        #expect(CyclePrediction.isInWindow(try TestClock.date(2026, 10, 31, 20), of: estimate, calendar: calendar))
        #expect(!CyclePrediction.isInWindow(try TestClock.date(2026, 11, 2), of: estimate, calendar: calendar))
    }

    @Test("Cycles of the same length still give a three-day window")
    func sameLength() throws {
        let estimate = try #require(CyclePrediction.summary(
            history(lengths: [28, 28, 28], lastStart: try TestClock.date(2026, 10, 1)),
            today: try TestClock.date(2026, 10, 6),
            calendar: calendar
        ).estimate)
        #expect(estimate.windowStart == calendar.startOfDay(for: try TestClock.date(2026, 10, 28)))
        #expect(estimate.windowEnd == calendar.startOfDay(for: try TestClock.date(2026, 10, 30)))
    }

    @Test("More than 7 days between the shortest and longest cycle is less certain; 7 is not")
    func lessCertain() throws {
        let lastStart = try TestClock.date(2026, 10, 1)
        let today = try TestClock.date(2026, 10, 6)
        let seven = CyclePrediction.summary(history(lengths: [26, 33], lastStart: lastStart), today: today, calendar: calendar)
        let eight = CyclePrediction.summary(history(lengths: [26, 34], lastStart: lastStart), today: today, calendar: calendar)
        #expect(seven.estimate?.isLessCertain == false)
        #expect(eight.estimate?.isLessCertain == true)
    }

    @Test("A cycle outside 15–60 days is left out of the estimate, but still listed")
    func implausible() throws {
        let summary = CyclePrediction.summary(
            history(lengths: [29, 90, 30], lastStart: try TestClock.date(2026, 10, 1)),
            today: try TestClock.date(2026, 10, 6),
            calendar: calendar
        )
        #expect(summary.completedCycles.count == 3)
        #expect(summary.estimate?.cycleCount == 2)
        #expect(summary.estimate?.longestDays == 30)
    }

    @Test("When every cycle is outside 15–60 days there's no estimate, though the cycles are listed")
    func allExcluded() throws {
        let summary = CyclePrediction.summary(
            history(lengths: [70, 90, 12], lastStart: try TestClock.date(2026, 10, 1)),
            today: try TestClock.date(2026, 10, 6),
            calendar: calendar
        )
        #expect(summary.completedCycles.count == 3)
        #expect(summary.estimate == nil)
        #expect(summary.daysUntilExpected == nil)
        #expect(!summary.isPastWindow)
        #expect(summary.cycleDay == 6)
    }

    @Test("After the window, the summary says so and the expected day is in the past")
    func late() throws {
        let summary = CyclePrediction.summary(
            history(lengths: [28, 30], lastStart: try TestClock.date(2026, 9, 1)),
            today: try TestClock.date(2026, 10, 6),
            calendar: calendar
        )
        #expect(summary.isPastWindow)
        #expect(summary.daysUntilExpected == -6)
        #expect(summary.cycleDay == 36)
    }

    @Test("A daylight saving change doesn't shift cycle days")
    func daylightSaving() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        // Clocks go back on 25 October 2026.
        let start = try TestClock.date(2026, 10, 20, 0, 30, calendar: berlin)
        let today = try TestClock.date(2026, 10, 30, 23, 30, calendar: berlin)
        let summary = CyclePrediction.summary([CycleDay(id: UUID(), day: start, flow: .light, symptoms: [], note: nil)], today: today, calendar: berlin)
        #expect(summary.cycleDay == 11)
    }
}
