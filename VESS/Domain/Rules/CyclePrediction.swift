import Foundation

/// Cycle tracking (13): periods from logged days, cycle lengths, today's
/// cycle day, and when the next period is likely to start.
///
/// - A period is a run of light, medium or heavy flow days. Up to
///   `periodGapDays` days without flow inside a run (a day not logged)
///   don't split it. Spotting never starts or extends a period.
/// - A cycle runs from one period's first day to the next one's. The last
///   period starts the current, unfinished cycle.
/// - The estimate uses the last `maxCycles` completed cycles and needs at
///   least `minCycles`. Cycles outside `plausibleDays` are left out, as they
///   usually mean a period wasn't logged.
/// - The expected start is the last start plus the rounded average. The
///   window runs from the last start plus the shortest of those cycles to
///   the last start plus the longest; when they are all the same length,
///   one day either side.
/// - When the cycles differ by more than `variableSpreadDays`, the estimate
///   is less certain, and the screen says so.
///
/// Estimates only: no fertile window, ovulation or pregnancy. Pure and
/// deterministic; days are counted in calendar days, so daylight saving
/// changes never shift them.
nonisolated enum CyclePrediction {
    static let maxCycles = 6
    static let minCycles = 2
    static let variableSpreadDays = 7
    static let periodGapDays = 2
    static let plausibleDays = 15...60

    nonisolated struct Period: Equatable, Sendable {
        let start: Date
        let lastDay: Date
        let lengthDays: Int
    }

    /// A cycle, newest first in `Summary.cycles`.
    nonisolated struct Cycle: Equatable, Sendable {
        let start: Date
        let periodDays: Int
        /// `nil` for the current cycle.
        let lengthDays: Int?
    }

    nonisolated struct Estimate: Equatable, Sendable {
        let expected: Date
        let windowStart: Date
        let windowEnd: Date
        let averageDays: Int
        let shortestDays: Int
        let longestDays: Int
        /// How many completed cycles it's based on (2…6).
        let cycleCount: Int
        let isLessCertain: Bool
    }

    nonisolated struct Summary: Equatable, Sendable {
        /// Oldest first.
        let periods: [Period]
        /// Newest first; the first is the current cycle.
        let cycles: [Cycle]
        /// Today's day in the current cycle, from 1.
        let cycleDay: Int?
        let estimate: Estimate?
        /// Days from today to the expected start; negative once it's passed.
        let daysUntilExpected: Int?
        /// Today is after the window's last day.
        let isPastWindow: Bool

        var completedCycles: [Cycle] { cycles.filter { $0.lengthDays != nil } }
    }

    static func summary(_ days: [CycleDay], today: Date, calendar: Calendar) -> Summary {
        let periods = periods(days, upTo: today, calendar: calendar)
        var cycles: [Cycle] = []
        for (index, period) in periods.enumerated() {
            let next = periods.indices.contains(index + 1) ? periods[index + 1] : nil
            cycles.append(Cycle(
                start: period.start,
                periodDays: period.lengthDays,
                lengthDays: next.map { daysBetween(period.start, $0.start, calendar: calendar) }
            ))
        }
        cycles.reverse()

        guard let last = periods.last else {
            return Summary(periods: [], cycles: [], cycleDay: nil, estimate: nil, daysUntilExpected: nil, isPastWindow: false)
        }
        let estimate = estimate(lastStart: last.start, cycles: cycles, calendar: calendar)
        let cycleDay = daysBetween(last.start, today, calendar: calendar) + 1
        return Summary(
            periods: periods,
            cycles: cycles,
            cycleDay: cycleDay,
            estimate: estimate,
            daysUntilExpected: estimate.map { daysBetween(today, $0.expected, calendar: calendar) },
            isPastWindow: estimate.map { daysBetween($0.windowEnd, today, calendar: calendar) > 0 } ?? false
        )
    }

    /// Periods that started on or before `today`, oldest first.
    static func periods(_ days: [CycleDay], upTo today: Date, calendar: Calendar) -> [Period] {
        let end = calendar.startOfDay(for: today)
        let bleeding = Set(days.filter { $0.flow.isPeriod }.map { calendar.startOfDay(for: $0.day) })
            .filter { $0 <= end }
            .sorted()
        var periods: [Period] = []
        var start: Date?
        var lastDay: Date?
        for day in bleeding {
            if let current = lastDay, daysBetween(current, day, calendar: calendar) <= periodGapDays + 1 {
                lastDay = day
            } else {
                if let start, let lastDay {
                    periods.append(Period(start: start, lastDay: lastDay, lengthDays: daysBetween(start, lastDay, calendar: calendar) + 1))
                }
                start = day
                lastDay = day
            }
        }
        if let start, let lastDay {
            periods.append(Period(start: start, lastDay: lastDay, lengthDays: daysBetween(start, lastDay, calendar: calendar) + 1))
        }
        return periods
    }

    /// Whether `date` falls in the estimate's window.
    static func isInWindow(_ date: Date, of estimate: Estimate, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= estimate.windowStart && day <= estimate.windowEnd
    }

    private static func estimate(lastStart: Date, cycles: [Cycle], calendar: Calendar) -> Estimate? {
        let lengths = cycles.compactMap(\.lengthDays).filter { plausibleDays.contains($0) }.prefix(maxCycles)
        guard lengths.count >= minCycles, let shortest = lengths.min(), let longest = lengths.max() else { return nil }
        let average = Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
        func offset(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: lastStart) ?? lastStart
        }
        let isSame = shortest == longest
        return Estimate(
            expected: offset(average),
            windowStart: offset(isSame ? average - 1 : shortest),
            windowEnd: offset(isSame ? average + 1 : longest),
            averageDays: average,
            shortestDays: shortest,
            longestDays: longest,
            cycleCount: lengths.count,
            isLessCertain: longest - shortest > variableSpreadDays
        )
    }

    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }
}
