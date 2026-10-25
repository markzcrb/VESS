import Foundation
import Testing
@testable import VESS

@Suite("Health: sleep, heart, stress, body")
struct HealthRulesTests {
    private let calendar = TestClock.utc

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try TestClock.date(2026, 10, day, hour, minute)
    }

    private func sample(_ start: Date, _ minutes: Double, _ stage: SleepSample.Stage, watch: Bool = true) -> SleepSample {
        SleepSample(start: start, end: start.addingTimeInterval(minutes * 60), stage: stage, isWatch: watch)
    }

    // MARK: Sleep

    @Test("Last night: the main session ending between 03:00 and 14:00 today; a nap doesn't count")
    func lastNight() throws {
        let samples = [
            sample(try at(5, 23, 48), 78, .deep), sample(try at(6, 1, 6), 238, .core), sample(try at(6, 5, 4), 94, .rem),
            sample(try at(6, 6, 38), 22, .awake),
            // An afternoon nap ends at 15:30: not last night.
            sample(try at(6, 15, 0), 30, .asleep),
        ]
        let nights = SleepRules.nights(samples, calendar: calendar)
        let night = try #require(SleepRules.lastNight(nights, now: try at(6, 18, 40), calendar: calendar))
        let start = try at(5, 23, 48)
        let end = try at(6, 7, 0)
        #expect(night.start == start && night.end == end)
        #expect(night.asleepMinutes == 78 + 238 + 94, "7 h 12, awake not counted")
        #expect(night.stages[.deep] == 78 && night.stages[.awake] == 22 && night.hasStages)
        #expect(nights.count == 1)
    }

    @Test("Sources are merged; where the Watch and the iPhone overlap, the Watch wins")
    func watchWins() throws {
        let samples = [
            sample(try at(5, 23, 0), 480, .inBed, watch: false),
            sample(try at(5, 23, 30), 420, .core, watch: true),
        ]
        let night = try #require(SleepRules.nights(samples, calendar: calendar).first)
        #expect(night.asleepMinutes == 420 && night.isWatch)
        // Only the iPhone's in-bed time: that's what's shown, without stages.
        let phone = try #require(SleepRules.nights([sample(try at(5, 23, 0), 480, .inBed, watch: false)], calendar: calendar).first)
        #expect(phone.asleepMinutes == 480 && !phone.hasStages)
    }

    @Test("Usual: the median of the 28 nights before; bedtime likewise")
    func usual() throws {
        let nights = (1...5).map { offset in
            SleepRules.Night(day: try! at(offset, 0), start: try! at(offset, 0).addingTimeInterval(-30 * 60), end: try! at(offset, 7),
                             asleepMinutes: Double(400 + offset * 10), stages: [:], isWatch: true)
        }
        #expect(SleepRules.usualMinutes(nights, before: try at(6, 0), calendar: calendar) == 430)
        #expect(SleepRules.usualBedtime(nights, before: try at(6, 0), calendar: calendar) == -30)
        #expect(SleepRules.usualMinutes(Array(nights.prefix(2)), before: try at(6, 0), calendar: calendar) == nil, "At least 3 nights")
    }

    // MARK: Heart

    @Test("Heart: the usual range is the middle 80 % of 30 days; the ring shows where today sits")
    func heart() throws {
        let values = (1...30).map { DailyValue(day: try! TestClock.date(2026, 9, 6).addingTimeInterval(Double($0) * 86_400), value: Double(50 + $0 % 11)) }
        let range = try #require(HeartRules.usualRange(values, before: try at(6, 0), calendar: calendar))
        #expect(range.lowerBound > 50 && range.upperBound < 60)
        #expect(HeartRules.ringFraction(range.lowerBound, in: range) == 0 && HeartRules.ringFraction(99, in: range) == 1)
        #expect(HeartRules.compare(47, to: 52) == .close)
        #expect(HeartRules.compare(45, to: 52) == .aLittleBelow)
        #expect(HeartRules.compare(40, to: 52) == .below)
        #expect(HeartRules.rangeToday([HourlyRange(start: .now, min: 49, max: 90), HourlyRange(start: .now, min: 60, max: 142)]) == 49...142)
    }

    // MARK: Stress

    @Test("Stress classification", arguments: [
        // (HRV, resting HR) against a 50 ms / 60 bpm baseline.
        (50.0, 60.0, StressRules.Level.calm),
        (42.5, 63.0, .elevated),   // 15 % below, 5 % above
        (43.0, 63.0, .calm),       // 14 % below
        (42.5, 62.9, .calm),       // RHR only 4.8 % above
        (35.0, 66.0, .high),       // 30 % below, 10 % above
        (35.0, 65.0, .elevated),   // RHR 8.3 % above: elevated, not high
        (30.0, 55.0, .calm),       // HRV low but RHR lower: both must move
    ])
    func classify(hrv: Double, rhr: Double, expected: StressRules.Level) {
        let baseline = StressRules.Baseline(hrv: 50, restingHeartRate: 60, days: 28)
        #expect(StressRules.classify(hrv: hrv, restingHeartRate: rhr, baseline: baseline) == expected)
    }

    @Test("The baseline needs 14 days of overnight HRV and resting HR; parts of the day use daytime samples")
    func baseline() throws {
        let now = try at(30, 18, 0)
        func days(_ count: Int) -> ([TimedValue], [DailyValue]) {
            var hrv: [TimedValue] = []
            var rhr: [DailyValue] = []
            for offset in 1...count {
                let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))!
                hrv.append(TimedValue(date: day.addingTimeInterval(3 * 3600), value: 50))
                rhr.append(DailyValue(day: day, value: 60))
            }
            return (hrv, rhr)
        }
        let (fewHRV, fewRHR) = days(10)
        #expect(StressRules.estimate(hrvSamples: fewHRV, restingHeartRate: fewRHR, now: now, calendar: calendar) == .building(days: 10))

        var (hrv, rhr) = days(20)
        let today = calendar.startOfDay(for: now)
        hrv.append(TimedValue(date: today.addingTimeInterval(3 * 3600), value: 49))
        hrv.append(TimedValue(date: today.addingTimeInterval(9 * 3600), value: 50))   // morning: calm
        hrv.append(TimedValue(date: today.addingTimeInterval(14 * 3600), value: 40))  // afternoon: 20 % below
        rhr.append(DailyValue(day: today, value: 64))                                  // 6.7 % above
        let estimate = StressRules.estimate(hrvSamples: hrv, restingHeartRate: rhr, now: now, calendar: calendar)
        #expect(estimate == .estimate(today: .calm, parts: [.morning: .calm, .afternoon: .elevated]))
    }

    // MARK: Body

    @Test("BMI: adults only, not during pregnancy; Health's weight wins when newer")
    func bmi() throws {
        var profile = MockData(now: .now, calendar: calendar).profile
        profile.heightCentimeters = 182
        profile.weightKilograms = 80
        profile.updatedAt = try at(1, 9)
        #expect(BodyRules.showsBMI(profile: profile, now: try at(6, 9), calendar: calendar))
        let newer = BodyMassSample(kilograms: 78.4, measuredAt: try at(6, 7))
        #expect(abs((BodyRules.bmi(profile: profile, health: newer) ?? 0) - 23.67) < 0.01)
        let older = BodyMassSample(kilograms: 70, measuredAt: try TestClock.date(2026, 9, 1))
        #expect(BodyRules.weight(profile: profile, health: older) == 80)
        #expect(BodyRules.Range(23.7) == .from18_5to25 && BodyRules.Range(30) == .from30 && BodyRules.Range(18.4) == .below18_5)

        var teen = profile
        teen.dateOfBirth = calendar.date(byAdding: .year, value: -17, to: try at(6, 9))
        #expect(!BodyRules.showsBMI(profile: teen, now: try at(6, 9), calendar: calendar), "Hidden under 18")
        var pregnant = profile
        pregnant.sex = .female
        pregnant.isPregnant = true
        #expect(!BodyRules.showsBMI(profile: pregnant, now: try at(6, 9), calendar: calendar), "Hidden during pregnancy")
        pregnant.goal = .loseWeight
        #expect(pregnant.effectiveGoal == .maintainWeight, "No weight-loss goal during pregnancy")
        var male = profile
        male.sex = .male
        male.isPregnant = true
        #expect(!male.pregnant && !male.canBePregnant, "The switch isn't offered for Male; a stored value is ignored")
    }

    // MARK: Demo

    @Test("The demo data gives H01–H03 their designed values")
    func demo() throws {
        let now = try at(6, 18, 40)
        let health = MockData(now: now, calendar: calendar).health
        let nights = SleepRules.nights(health.sleep, calendar: calendar)
        let last = try #require(SleepRules.lastNight(nights, now: now, calendar: calendar))
        let wake = try at(6, 7, 6)
        #expect(last.asleepMinutes == 432 && last.end == wake)
        #expect(SleepRules.usualMinutes(nights, before: last.day, calendar: calendar) == 440)
        #expect(SleepRules.bedtime(last) - (SleepRules.usualBedtime(nights, before: last.day, calendar: calendar) ?? 0) == 40)
        let week = SleepRules.week(nights, now: now, calendar: calendar).compactMap(\.minutes)
        #expect((week.reduce(0, +) / Double(week.count)).rounded() == 425, "7 h 05")

        let range = try #require(HeartRules.usualRange(health.restingHeartRate, before: now, calendar: calendar))
        #expect(range.lowerBound.rounded() == 56 && range.upperBound.rounded() == 61)
        let overnight = StressRules.overnightHRV(health.heartRateVariability, calendar: calendar)
        #expect(HeartRules.average(overnight, before: now, calendar: calendar)?.rounded() == 53)
        #expect(HeartRules.compare(47, to: 53) == .aLittleBelow)

        let estimate = StressRules.estimate(hrvSamples: health.heartRateVariability, restingHeartRate: health.restingHeartRate, now: now, calendar: calendar)
        #expect(estimate == .estimate(today: .calm, parts: [.morning: .calm, .afternoon: .elevated, .evening: .calm]))
        let days: Int = TrendRule.patternMinimumDays
        let afternoons: [Date: StressRules.Level] = StressRules.pastAfternoons(
            hrvSamples: health.heartRateVariability, restingHeartRate: health.restingHeartRate, days: days, now: now, calendar: calendar
        )
        let pattern = try #require(TrendRule.shortSleepAfternoons(nights: nights, afternoons: afternoons, now: now, calendar: calendar))
        #expect(pattern.afterShort == 4 && pattern.elevated == 5)
    }

    // MARK: Patterns

    @Test("Late dinners and sleep: a pattern only with five weeks, 4 nights each way and 15 minutes' difference")
    func lateDinnerPattern() throws {
        let now = try TestClock.date(2026, 11, 20, 18)
        var nights: [SleepRules.Night] = []
        var entries: [FoodLogEntry] = []
        let user = UUID()
        for offset in 1...40 {
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))!
            let start = day.addingTimeInterval(-60 * 60)        // 23:00 the evening before
            let late = offset % 3 == 0
            nights.append(.init(day: day, start: start, end: day.addingTimeInterval(7 * 3600), asleepMinutes: late ? 410 : 440, stages: [:], isWatch: true))
            let dinner = start.addingTimeInterval(late ? -1.5 * 3600 : -4 * 3600)
            entries.append(FoodLogEntry(id: UUID(), userID: user, foodID: nil, foodName: "Dinner", mealType: .dinner, quantity: 1,
                                        servingUnit: .serving, nutrition: .zero, loggedAt: dinner))
        }
        let pattern = try #require(TrendRule.lateDinnerSleep(nights: nights.sorted { $0.day < $1.day }, entries: entries, now: now, calendar: calendar))
        #expect(pattern.minutesLess == 30 && pattern.weeks >= 5)
        #expect(TrendRule.lateDinnerSleep(nights: Array(nights.prefix(20)).sorted { $0.day < $1.day }, entries: entries, now: now, calendar: calendar) == nil,
                "Under five weeks: no pattern yet")
    }
}
