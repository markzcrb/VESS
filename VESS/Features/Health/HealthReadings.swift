import Foundation

/// Everything H00–H03 show, worked out once from Apple Health's snapshot
/// with the rules in `HealthRules.swift`. Views only render this.
struct HealthReadings {
    let nights: [SleepRules.Night]
    let lastNight: SleepRules.Night?
    let usualSleepMinutes: Double?
    /// Minutes later (positive) or earlier than the usual bedtime.
    let bedtimeDifference: Double?
    let week: [(day: Date, value: Double?)]

    let restingToday: Double?
    let restingUsual: ClosedRange<Double>?
    let restingAverage: Double?
    let restingWeek: [(day: Date, value: Double?)]
    let hrvToday: Double?
    let hrvAverage: Double?
    let walkingToday: Double?
    let rangeToday: ClosedRange<Double>?

    let stress: StressRules.Estimate?
    let pastAfternoons: [Date: StressRules.Level]

    init(snapshot: HealthSnapshot, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        nights = SleepRules.nights(snapshot.sleep, calendar: calendar)
        lastNight = SleepRules.lastNight(nights, now: now, calendar: calendar)
        usualSleepMinutes = SleepRules.usualMinutes(nights, before: today, calendar: calendar)
        if let lastNight, let usual = SleepRules.usualBedtime(nights, before: today, calendar: calendar) {
            bedtimeDifference = SleepRules.bedtime(lastNight) - usual
        } else {
            bedtimeDifference = nil
        }
        week = SleepRules.week(nights, now: now, calendar: calendar).map { ($0.day, $0.minutes) }

        restingToday = HeartRules.value(on: now, snapshot.restingHeartRate, calendar: calendar)
        restingUsual = HeartRules.usualRange(snapshot.restingHeartRate, before: now, calendar: calendar)
        restingAverage = HeartRules.average(snapshot.restingHeartRate, before: now, calendar: calendar)
        restingWeek = (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, HeartRules.value(on: day, snapshot.restingHeartRate, calendar: calendar))
        }
        let overnight = StressRules.overnightHRV(snapshot.heartRateVariability, calendar: calendar)
        hrvToday = HeartRules.value(on: now, overnight, calendar: calendar)
        hrvAverage = HeartRules.average(overnight, before: now, calendar: calendar)
        walkingToday = HeartRules.value(on: now, snapshot.walkingHeartRate, calendar: calendar)
        rangeToday = HeartRules.rangeToday(snapshot.heartRateToday)

        stress = StressRules.estimate(
            hrvSamples: snapshot.heartRateVariability, restingHeartRate: snapshot.restingHeartRate, now: now, calendar: calendar
        )
        pastAfternoons = StressRules.pastAfternoons(
            hrvSamples: snapshot.heartRateVariability, restingHeartRate: snapshot.restingHeartRate,
            days: TrendRule.patternMinimumDays, now: now, calendar: calendar
        )
    }

    /// The 7-night average of the nights there were.
    var weekAverage: Double? {
        let known = week.compactMap(\.value)
        return known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
    }

    /// Where today's resting heart rate sits against the usual range.
    var restingComparison: HeartRules.Comparison? {
        guard let restingToday, let restingUsual else { return nil }
        if restingToday < restingUsual.lowerBound.rounded() { return .below }
        if restingToday > restingUsual.upperBound.rounded() { return .above }
        return .close
    }

    var hrvComparison: HeartRules.Comparison? {
        guard let hrvToday, let hrvAverage else { return nil }
        return HeartRules.compare(hrvToday, to: hrvAverage)
    }

    /// Last night against the usual: within 15 minutes is "close".
    var sleepDifference: Double? {
        guard let lastNight, let usualSleepMinutes else { return nil }
        return lastNight.asleepMinutes - usualSleepMinutes
    }
}
