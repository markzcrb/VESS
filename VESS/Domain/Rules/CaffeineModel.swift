import Foundation

/// Caffeine logged in a day against a daily limit, and an estimate of how
/// much is still in the body over time. Pure and deterministic.
///
/// The estimate assumes each drink's caffeine is absorbed when it's logged
/// and halves every `halfLifeHours`. It's labelled as an estimate wherever
/// it's shown; real half-lives vary from person to person.
nonisolated enum CaffeineModel {
    /// The daily limit VESS compares against, in mg.
    static let dailyLimitMilligrams = 400.0
    /// Hours for the amount in the body to halve.
    static let halfLifeHours = 5.0

    /// One sample of the estimate.
    struct Point: Equatable, Sendable {
        let date: Date
        let milligrams: Double
    }

    /// mg logged on `day`'s calendar day.
    static func total(_ logs: [HydrationLog], on day: Date, calendar: Calendar) -> Double {
        logs.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
            .reduce(0) { $0 + $1.caffeineMilligrams }
    }

    /// Share of the daily limit, 0... (may exceed 1).
    static func limitShare(of milligrams: Double) -> Double {
        milligrams / dailyLimitMilligrams
    }

    /// Estimated mg in the body at `date`, from every drink logged at or
    /// before it (drinks from the evening before still count).
    static func remaining(_ logs: [HydrationLog], at date: Date) -> Double {
        logs.reduce(0) { sum, log in
            guard log.caffeineMilligrams > 0, log.loggedAt <= date else { return sum }
            let hours = date.timeIntervalSince(log.loggedAt) / 3600
            return sum + log.caffeineMilligrams * pow(0.5, hours / halfLifeHours)
        }
    }

    /// The estimate from `start` to `end` every `step`, including both ends
    /// and a sample at each drink so steps up are drawn where they happen.
    static func curve(_ logs: [HydrationLog], from start: Date, to end: Date, step: TimeInterval = 600) -> [Point] {
        guard end > start, step > 0 else { return [] }
        var dates: [Date] = []
        var date = start
        while date < end {
            dates.append(date)
            date = date.addingTimeInterval(step)
        }
        dates.append(end)
        for log in logs where log.caffeineMilligrams > 0 && log.loggedAt > start && log.loggedAt < end {
            // Just before and at the drink: a vertical step.
            dates.append(log.loggedAt.addingTimeInterval(-1))
            dates.append(log.loggedAt)
        }
        return dates.sorted().map { Point(date: $0, milligrams: remaining(logs, at: $0)) }
    }

    /// 22:00 on `day`, the time the screen's estimate refers to.
    static func evening(of day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day) ?? day
    }
}
