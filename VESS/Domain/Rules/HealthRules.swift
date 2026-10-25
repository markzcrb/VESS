import Foundation

// Sleep, heart, stress and body (H01–H04): pure, deterministic rules over
// what Apple Health shares. Nothing here is a diagnosis; screens say so.

// MARK: - Sleep

nonisolated enum SleepRules {
    /// One night: the main sleep session ending on `day`.
    nonisolated struct Night: Equatable, Sendable {
        /// The start of the day the user woke up.
        let day: Date
        let start: Date
        let end: Date
        /// Time asleep (stages or "asleep"); in-bed time when that's all there is.
        let asleepMinutes: Double
        /// Minutes per stage; empty without stage data.
        let stages: [SleepSample.Stage: Double]
        var hasStages: Bool { stages[.core] != nil || stages[.deep] != nil || stages[.rem] != nil }
        let isWatch: Bool
    }

    /// Samples this close together belong to one session.
    static let sessionGap: TimeInterval = 60 * 60
    /// "Last night" ends between 03:00 and 14:00.
    static let earliestWake = 3
    static let latestWake = 14

    /// The main night for each day it ended on, oldest first. Samples from
    /// every source are merged; where an Apple Watch and another source
    /// overlap, the Watch wins.
    static func nights(_ samples: [SleepSample], calendar: Calendar) -> [Night] {
        let watch = samples.filter(\.isWatch)
        let others = samples.filter { sample in
            !sample.isWatch && !watch.contains { $0.start < sample.end && sample.start < $0.end }
        }
        let sorted = (watch + others).sorted { $0.start < $1.start }

        var sessions: [[SleepSample]] = []
        for sample in sorted {
            if let last = sessions.last?.map(\.end).max(), sample.start.timeIntervalSince(last) <= sessionGap {
                sessions[sessions.count - 1].append(sample)
            } else {
                sessions.append([sample])
            }
        }

        var best: [Date: Night] = [:]
        for session in sessions {
            guard let night = night(session, calendar: calendar) else { continue }
            let hour = calendar.component(.hour, from: night.end)
            guard hour >= earliestWake && hour < latestWake else { continue }
            if (best[night.day]?.asleepMinutes ?? -1) < night.asleepMinutes { best[night.day] = night }
        }
        return best.values.sorted { $0.day < $1.day }
    }

    private static func night(_ session: [SleepSample], calendar: Calendar) -> Night? {
        guard let start = session.map(\.start).min(), let end = session.map(\.end).max() else { return nil }
        let asleep = union(session.filter(\.stage.isAsleep))
        let inBed = union(session.filter { $0.stage == .inBed })
        let minutes = (asleep > 0 ? asleep : inBed) / 60
        guard minutes > 0 else { return nil }
        var stages: [SleepSample.Stage: Double] = [:]
        for stage in [SleepSample.Stage.deep, .core, .rem, .awake] {
            let total = union(session.filter { $0.stage == stage }) / 60
            if total > 0 { stages[stage] = total }
        }
        if stages[.core] == nil && stages[.deep] == nil && stages[.rem] == nil { stages = [:] }
        return Night(
            day: calendar.startOfDay(for: end), start: start, end: end, asleepMinutes: minutes,
            stages: stages, isWatch: session.contains(where: \.isWatch)
        )
    }

    /// Seconds covered by the samples, overlaps counted once.
    private static func union(_ samples: [SleepSample]) -> TimeInterval {
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for sample in samples.sorted(by: { $0.start < $1.start }) {
            if let open = current, sample.start <= open.end {
                current = (open.start, max(open.end, sample.end))
            } else {
                if let open = current { total += open.end.timeIntervalSince(open.start) }
                current = (sample.start, sample.end)
            }
        }
        if let open = current { total += open.end.timeIntervalSince(open.start) }
        return total
    }

    /// Last night: the main session that ended today (03:00–14:00), if it has.
    static func lastNight(_ nights: [Night], now: Date, calendar: Calendar) -> Night? {
        nights.last { calendar.isDate($0.day, inSameDayAs: now) && $0.end <= now }
    }

    /// "Usual": the median over the 28 nights before `day`; at least 3 nights.
    static let usualWindowDays = 28

    static func usualMinutes(_ nights: [Night], before day: Date, calendar: Calendar) -> Double? {
        median(window(nights, before: day, calendar: calendar).map(\.asleepMinutes))
    }

    /// The usual time of falling asleep, in minutes from the wake day's
    /// midnight (negative before midnight).
    static func usualBedtime(_ nights: [Night], before day: Date, calendar: Calendar) -> Double? {
        median(window(nights, before: day, calendar: calendar).map { bedtime($0) })
    }

    static func bedtime(_ night: Night) -> Double {
        night.start.timeIntervalSince(night.day) / 60
    }

    private static func window(_ nights: [Night], before day: Date, calendar: Calendar) -> [Night] {
        guard let start = calendar.date(byAdding: .day, value: -usualWindowDays, to: day) else { return [] }
        let recent = nights.filter { $0.day >= start && $0.day < day }
        return recent.count >= 3 ? recent : []
    }

    /// The 7 nights ending today, oldest first; `nil` where there was none.
    static func week(_ nights: [Night], now: Date, calendar: Calendar) -> [(day: Date, minutes: Double?)] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, nights.first { $0.day == day }?.asleepMinutes)
        }
    }
}

// MARK: - Heart

nonisolated enum HeartRules {
    static let windowDays = 30

    /// The user's usual resting heart rate: the middle 80 % (10th to 90th
    /// percentile) of the 30 days before today; at least 7 days.
    static func usualRange(_ values: [DailyValue], before day: Date, calendar: Calendar) -> ClosedRange<Double>? {
        let prior = window(values, before: day, calendar: calendar).map(\.value).sorted()
        guard prior.count >= 7 else { return nil }
        return percentile(prior, 0.1)...percentile(prior, 0.9)
    }

    static func average(_ values: [DailyValue], before day: Date, calendar: Calendar) -> Double? {
        let prior = window(values, before: day, calendar: calendar).map(\.value)
        guard prior.count >= 7 else { return nil }
        return prior.reduce(0, +) / Double(prior.count)
    }

    static func value(on day: Date, _ values: [DailyValue], calendar: Calendar) -> Double? {
        values.last { calendar.isDate($0.day, inSameDayAs: day) }?.value
    }

    /// Where today sits within the usual range, 0…1, for the ring.
    static func ringFraction(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return 0.5 }
        return min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    /// Today's lowest and highest heart rate.
    static func rangeToday(_ hours: [HourlyRange]) -> ClosedRange<Double>? {
        guard let low = hours.map(\.min).min(), let high = hours.map(\.max).max() else { return nil }
        return low...high
    }

    nonisolated enum Comparison: Equatable, Sendable { case below, aLittleBelow, close, aLittleAbove, above }

    /// Within 10 % is close; 10–20 % a little; more is above or below.
    static func compare(_ value: Double, to average: Double) -> Comparison {
        guard average > 0 else { return .close }
        let ratio = value / average - 1
        switch ratio {
        case ..<(-0.2): return .below
        case ..<(-0.1): return .aLittleBelow
        case ...0.1: return .close
        case ...0.2: return .aLittleAbove
        default: return .above
        }
    }

    private static func window(_ values: [DailyValue], before day: Date, calendar: Calendar) -> [DailyValue] {
        let start = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: day)) ?? day
        return values.filter { $0.day >= start && $0.day < calendar.startOfDay(for: day) }
    }
}

// MARK: - Stress

/// An estimate from heart rate variability and resting heart rate against
/// the user's own baseline. Never a medical measurement. State of Mind and
/// mindful minutes are shown as signals and never change the result.
nonisolated enum StressRules {
    nonisolated enum Level: String, Equatable, Sendable { case calm, elevated, high }

    nonisolated enum PartOfDay: CaseIterable, Sendable {
        case morning, afternoon, evening

        /// Hours from, to (06–12, 12–18, 18–22).
        var hours: Range<Int> {
            switch self {
            case .morning: 6..<12
            case .afternoon: 12..<18
            case .evening: 18..<22
            }
        }
    }

    nonisolated struct Baseline: Equatable, Sendable {
        let hrv: Double
        let restingHeartRate: Double
        /// Days with both values in the window.
        let days: Int
    }

    static let baselineDays = 28
    static let minimumDays = 14

    /// Overnight HRV per day: the median of samples between 00:00 and 08:00.
    static func overnightHRV(_ samples: [TimedValue], calendar: Calendar) -> [DailyValue] {
        let night = samples.filter { calendar.component(.hour, from: $0.date) < 8 }
        let byDay = Dictionary(grouping: night) { calendar.startOfDay(for: $0.date) }
        return byDay.compactMap { day, values in median(values.map(\.value)).map { DailyValue(day: day, value: $0) } }
            .sorted { $0.day < $1.day }
    }

    /// Medians of the 28 days before `day` that have both overnight HRV and
    /// resting heart rate. `days` counts them, also when below 14.
    static func baseline(hrv: [DailyValue], restingHeartRate: [DailyValue], before day: Date, calendar: Calendar) -> Baseline {
        let today = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .day, value: -baselineDays, to: today) ?? today
        let resting = Dictionary(restingHeartRate.map { (calendar.startOfDay(for: $0.day), $0.value) }, uniquingKeysWith: { _, last in last })
        let pairs = hrv.compactMap { value -> (Double, Double)? in
            let day = calendar.startOfDay(for: value.day)
            guard day >= start, day < today, let rhr = resting[day] else { return nil }
            return (value.value, rhr)
        }
        return Baseline(hrv: median(pairs.map(\.0)) ?? 0, restingHeartRate: median(pairs.map(\.1)) ?? 0, days: pairs.count)
    }

    /// HRV at least 30 % below and resting heart rate at least 10 % above
    /// the baseline: high; at least 15 % and 5 %: elevated; otherwise calm.
    static func classify(hrv: Double, restingHeartRate: Double, baseline: Baseline) -> Level {
        guard baseline.hrv > 0, baseline.restingHeartRate > 0 else { return .calm }
        let hrvDrop = 1 - hrv / baseline.hrv
        let rhrRise = restingHeartRate / baseline.restingHeartRate - 1
        if hrvDrop >= 0.30 && rhrRise >= 0.10 { return .high }
        if hrvDrop >= 0.15 && rhrRise >= 0.05 { return .elevated }
        return .calm
    }

    nonisolated enum Estimate: Equatable, Sendable {
        /// Fewer than 14 days of both values: "Building your baseline · N of 14 days".
        case building(days: Int)
        case estimate(today: Level, parts: [PartOfDay: Level])
    }

    /// A part of the day from its daytime HRV alone (resting heart rate is
    /// one value per day, so it can't tell parts apart): at least 30 % below
    /// the baseline is high, at least 15 % elevated.
    static func classify(hrv: Double, baseline: Baseline) -> Level {
        guard baseline.hrv > 0 else { return .calm }
        let hrvDrop = 1 - hrv / baseline.hrv
        if hrvDrop >= 0.30 { return .high }
        if hrvDrop >= 0.15 { return .elevated }
        return .calm
    }

    /// Today's estimate, and each part of the day so far from that part's
    /// daytime HRV samples.
    static func estimate(hrvSamples: [TimedValue], restingHeartRate: [DailyValue], now: Date, calendar: Calendar) -> Estimate? {
        let overnight = overnightHRV(hrvSamples, calendar: calendar)
        let base = baseline(hrv: overnight, restingHeartRate: restingHeartRate, before: now, calendar: calendar)
        guard base.days >= minimumDays else { return .building(days: base.days) }
        guard let hrvToday = HeartRules.value(on: now, overnight, calendar: calendar),
              let rhrToday = HeartRules.value(on: now, restingHeartRate, calendar: calendar) else { return nil }
        return .estimate(
            today: classify(hrv: hrvToday, restingHeartRate: rhrToday, baseline: base),
            parts: parts(hrvSamples, on: now, baseline: base, calendar: calendar)
        )
    }

    /// Afternoon levels for each of the `days` before `now` that has a
    /// baseline and afternoon samples, for the pattern on H03.
    static func pastAfternoons(hrvSamples: [TimedValue], restingHeartRate: [DailyValue], days: Int, now: Date, calendar: Calendar) -> [Date: Level] {
        let overnight = overnightHRV(hrvSamples, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var result: [Date: Level] = [:]
        for offset in 1...days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let base = baseline(hrv: overnight, restingHeartRate: restingHeartRate, before: day, calendar: calendar)
            guard base.days >= minimumDays, let level = parts(hrvSamples, on: day, baseline: base, calendar: calendar)[.afternoon] else { continue }
            result[day] = level
        }
        return result
    }

    static func parts(_ samples: [TimedValue], on day: Date, baseline: Baseline, calendar: Calendar) -> [PartOfDay: Level] {
        var result: [PartOfDay: Level] = [:]
        for part in PartOfDay.allCases {
            let values = samples.filter { calendar.isDate($0.date, inSameDayAs: day) && part.hours.contains(calendar.component(.hour, from: $0.date)) }
            if let hrv = median(values.map(\.value)) {
                result[part] = classify(hrv: hrv, baseline: baseline)
            }
        }
        return result
    }
}

// MARK: - Body

nonisolated enum BodyRules {
    /// WHO adult ranges.
    nonisolated enum Range: Equatable, Sendable {
        case below18_5, from18_5to25, from25to30, from30

        init(_ bmi: Double) {
            switch bmi {
            case ..<18.5: self = .below18_5
            case ..<25: self = .from18_5to25
            case ..<30: self = .from25to30
            default: self = .from30
            }
        }
    }

    static let minimumAge = 18

    /// BMI is shown only to adults, and not during pregnancy.
    static func showsBMI(profile: UserProfile, now: Date, calendar: Calendar) -> Bool {
        guard !profile.pregnant else { return false }
        if let age = profile.age(on: now, calendar: calendar), age < minimumAge { return false }
        return true
    }

    /// The weight to use: Apple Health's latest when it is newer than the
    /// profile, otherwise the profile's.
    static func weight(profile: UserProfile, health: BodyMassSample?) -> Double {
        if let health, health.measuredAt > profile.updatedAt { return health.kilograms }
        return profile.weightKilograms
    }

    static func bmi(profile: UserProfile, health: BodyMassSample?) -> Double? {
        BodyMassIndex(weightKilograms: weight(profile: profile, health: health), heightCentimeters: profile.heightCentimeters)?.value
    }

    /// BMI over 12 weeks, from the weights in Apple Health.
    static func trend(_ weights: [BodyMassSample], heightCentimeters: Double) -> [TimedValue] {
        weights.compactMap { sample in
            BodyMassIndex(weightKilograms: sample.kilograms, heightCentimeters: heightCentimeters).map { TimedValue(date: sample.measuredAt, value: $0.value) }
        }
    }
}

// MARK: - Patterns

/// Patterns between days, as Insights shows them: only with at least five
/// weeks of data, always "a pattern, not a cause", hidden until found.
nonisolated extension TrendRule {
    static let patternMinimumDays = 35

    /// "On nights when you ate within 2 hours of bed, you slept about 25 min
    /// less." Late: the last food entry within 2 h before falling asleep.
    /// Needs 4 nights each way and at least 15 minutes' difference.
    static func lateDinnerSleep(nights: [SleepRules.Night], entries: [FoodLogEntry], now: Date, calendar: Calendar) -> (minutesLess: Int, weeks: Int)? {
        guard let first = nights.first?.day, now.timeIntervalSince(first) >= Double(patternMinimumDays) * 86_400 else { return nil }
        var late: [Double] = []
        var other: [Double] = []
        for night in nights {
            let lastMeal = entries.filter { $0.loggedAt < night.start && night.start.timeIntervalSince($0.loggedAt) < 12 * 3600 }.map(\.loggedAt).max()
            guard let lastMeal else { continue }
            if night.start.timeIntervalSince(lastMeal) <= 2 * 3600 { late.append(night.asleepMinutes) } else { other.append(night.asleepMinutes) }
        }
        guard late.count >= 4, other.count >= 4 else { return nil }
        let difference = other.reduce(0, +) / Double(other.count) - late.reduce(0, +) / Double(late.count)
        guard difference >= 15 else { return nil }
        let weeks = Int(now.timeIntervalSince(first) / (7 * 86_400))
        return (Int((difference / 5).rounded() * 5), weeks)
    }

    /// "Elevated afternoons followed nights with under 6 h of sleep (4 of
    /// 5)." Needs 4 elevated afternoons, 60 % of them after a short night.
    static func shortSleepAfternoons(nights: [SleepRules.Night], afternoons: [Date: StressRules.Level], now: Date, calendar: Calendar) -> (afterShort: Int, elevated: Int)? {
        guard let first = nights.first?.day, now.timeIntervalSince(first) >= Double(patternMinimumDays) * 86_400 else { return nil }
        let elevatedDays = afternoons.filter { $0.value != .calm }.map(\.key)
        guard elevatedDays.count >= 4 else { return nil }
        let afterShort = elevatedDays.count { day in
            (nights.first { calendar.isDate($0.day, inSameDayAs: day) }?.asleepMinutes ?? .infinity) < 6 * 60
        }
        guard Double(afterShort) / Double(elevatedDays.count) >= 0.6 else { return nil }
        return (afterShort, elevatedDays.count)
    }
}

// MARK: - Shared

private nonisolated func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

private nonisolated func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard sorted.count > 1 else { return sorted.first ?? 0 }
    let position = p * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = min(lower + 1, sorted.count - 1)
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
}
