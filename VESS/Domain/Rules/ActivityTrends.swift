import Foundation

/// Comparisons and patterns for Activity (PRODUCT-LOGIC.md, decided
/// 2026-10-21). Pure and deterministic. Everything is `nil` when there isn't
/// enough data, and screens then leave the comparison out.
nonisolated enum ActivityTrends {
    /// Past same weekdays that make "a typical Tuesday".
    static let typicalWeeks = 4
    /// Within ±10 % counts as about the same.
    static let sameBand = 0.10

    enum Comparison: Equatable, Sendable {
        case above, below, aboutSame
    }

    nonisolated struct DayTotal: Equatable, Sendable {
        let day: Date
        /// `nil` when Health has no samples for the day.
        let value: Double?
    }

    /// Weekends against weekdays, and the quietest weekday, over four full weeks.
    nonisolated struct WeeklyPattern: Equatable, Sendable {
        /// `true` weekends, `false` weekdays, `nil` about the same.
        let weekendsBusiest: Bool?
        /// `Calendar` weekday number (1 = Sunday).
        let quietestWeekday: Int
    }

    // MARK: Totals

    /// The sum on `day`, or `nil` without samples. With `cutoff`, only up to
    /// the same clock time on that day; the hour that contains it counts in
    /// proportion.
    static func total(_ values: [HourlyValue], on day: Date, upTo cutoff: Date? = nil, calendar: Calendar) -> Double? {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        let inDay = values.filter { $0.start >= start && $0.start < end }
        guard !inDay.isEmpty else { return nil }
        guard let cutoff else { return inDay.reduce(0) { $0 + $1.value } }

        let time = calendar.dateComponents([.hour, .minute], from: cutoff)
        guard let limit = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: start) else { return nil }
        return inDay.reduce(0) { sum, hour in
            let covered = min(max(limit.timeIntervalSince(hour.start) / 3600, 0), 1)
            return sum + hour.value * covered
        }
    }

    /// One total per day, oldest first, ending on `day`.
    static func dailyTotals(_ values: [HourlyValue], days: Int, endingOn day: Date, calendar: Calendar) -> [DayTotal] {
        let last = calendar.startOfDay(for: day)
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: last).map {
                DayTotal(day: $0, value: total(values, on: $0, calendar: calendar))
            }
        }
    }

    /// The mean over days with data; `nil` if none.
    static func average(_ totals: [DayTotal]) -> Double? {
        let known = totals.compactMap(\.value)
        return known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
    }

    // MARK: Comparisons

    /// "A typical Tuesday" at this time: the median of the last four same
    /// weekdays, each up to the same clock time. All four need data.
    static func typical(_ values: [HourlyValue], at time: Date, calendar: Calendar) -> Double? {
        let totals = (1...typicalWeeks).compactMap { week -> Double? in
            guard let day = calendar.date(byAdding: .day, value: -7 * week, to: time) else { return nil }
            return total(values, on: day, upTo: time, calendar: calendar)
        }
        guard totals.count == typicalWeeks else { return nil }
        return median(totals)
    }

    static func compare(_ value: Double, with reference: Double) -> Comparison {
        guard reference > 0 else { return value > 0 ? .above : .aboutSame }
        let ratio = value / reference
        if ratio > 1 + sameBand { return .above }
        if ratio < 1 - sameBand { return .below }
        return .aboutSame
    }

    /// The daily average over the last `days` days (today included) against
    /// the `days` before. The earlier period needs data on every day.
    static func periodComparison(_ values: [HourlyValue], days: Int, endingOn day: Date, calendar: Calendar) -> Comparison? {
        let both = dailyTotals(values, days: days * 2, endingOn: day, calendar: calendar)
        let earlier = Array(both.prefix(days))
        let recent = Array(both.suffix(days))
        guard earlier.allSatisfy({ $0.value != nil }),
              let before = average(earlier), let now = average(recent) else { return nil }
        return compare(now, with: before)
    }

    /// Needs data on each of the 28 days before `day`.
    static func weeklyPattern(_ values: [HourlyValue], before day: Date, calendar: Calendar) -> WeeklyPattern? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
        let totals = dailyTotals(values, days: 28, endingOn: yesterday, calendar: calendar)
        guard totals.allSatisfy({ $0.value != nil }) else { return nil }

        let byWeekday = Dictionary(grouping: totals) { calendar.component(.weekday, from: $0.day) }
            .compactMapValues { average($0) }
        let weekend = [1, 7].compactMap { byWeekday[$0] }
        let weekdays = (2...6).compactMap { byWeekday[$0] }
        guard weekend.count == 2, weekdays.count == 5,
              let quietest = byWeekday.min(by: { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value })?.key else { return nil }

        let busiest: Bool? = switch compare(weekend.reduce(0, +) / 2, with: weekdays.reduce(0, +) / 5) {
        case .above: true
        case .below: false
        case .aboutSame: nil
        }
        return WeeklyPattern(weekendsBusiest: busiest, quietestWeekday: quietest)
    }

    // MARK: Days and workouts

    /// The start of the hour with the most on `day`.
    static func mostActiveHour(_ values: [HourlyValue], on day: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return values
            .filter { $0.start >= start && $0.start < end && $0.value > 0 }
            .max { $0.value == $1.value ? $0.start > $1.start : $0.value < $1.value }?
            .start
    }

    /// Types by how often they appear, most first; ties go to the most recent.
    static func typesByFrequency(_ workouts: [Workout]) -> [(type: WorkoutType, count: Int)] {
        struct Group {
            let type: WorkoutType
            let count: Int
            let latest: Date
        }
        let groups: [Group] = Dictionary(grouping: workouts, by: \.type).map { type, items in
            Group(type: type, count: items.count, latest: items.compactMap(\.completedAt).max() ?? .distantPast)
        }
        let sorted = groups.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.latest > rhs.latest : lhs.count > rhs.count
        }
        return sorted.map { (type: $0.type, count: $0.count) }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
