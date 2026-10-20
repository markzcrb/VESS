import Foundation

/// The direction of today versus the user's recent days.
nonisolated enum Trend: Equatable, Sendable {
    case up, down, flat
}

/// "Today vs. prior 30 days": today's value so far against the average of
/// the previous 30 days, each counted only up to the same clock time.
///
/// - Only days that have at least one sample for the measure count as history.
/// - At least 7 such days are needed; otherwise there is no trend.
/// - More than 10 % above the average is up, more than 10 % below is down,
///   anything in between is flat.
///
/// Pure and deterministic.
nonisolated enum TrendRule {
    static let windowDays = 30
    static let minimumDays = 7
    static let threshold = 0.10

    /// One timestamped value, such as an entry's protein or a drink's hydration.
    struct Sample: Sendable {
        let date: Date
        let value: Double
    }

    /// Today so far against the prior days. `nil` without enough history or
    /// when the average is zero.
    static func trend(samples: [Sample], now: Date, calendar: Calendar) -> Trend? {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: today) else { return nil }
        let clock = secondsIntoDay(now, calendar: calendar)

        var todayValue = 0.0
        var priorTotals: [Date: Double] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            if day == today {
                if sample.date <= now { todayValue += sample.value }
            } else if day >= windowStart && day < today {
                // The day counts as history even if nothing was logged by this time.
                let upToClock = secondsIntoDay(sample.date, calendar: calendar) <= clock ? sample.value : 0
                priorTotals[day, default: 0] += upToClock
            }
        }

        guard priorTotals.count >= minimumDays else { return nil }
        let average = priorTotals.values.reduce(0, +) / Double(priorTotals.count)
        guard average > 0 else { return nil }
        let ratio = todayValue / average
        if ratio > 1 + threshold { return .up }
        if ratio < 1 - threshold { return .down }
        return .flat
    }

    private static func secondsIntoDay(_ date: Date, calendar: Calendar) -> TimeInterval {
        date.timeIntervalSince(calendar.startOfDay(for: date))
    }
}
