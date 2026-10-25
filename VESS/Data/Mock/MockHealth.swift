#if DEBUG
import Foundation

/// SAMPLE DATA for H00–H04, DEBUG only. Matches the designs: last night
/// 7 h 12 (23:48–07:06), usual 7 h 20; resting 58 bpm (usual 56–61), HRV
/// 47 ms against a 53 ms average; Calm today with an elevated afternoon;
/// more than five weeks of nights so the H03 pattern shows.
nonisolated extension MockData {
    struct HealthDemo {
        var sleep: [SleepSample] = []
        var restingHeartRate: [DailyValue] = []
        var heartRateVariability: [TimedValue] = []
        var walkingHeartRate: [DailyValue] = []
        var heartRateToday: [HourlyRange] = []
        var stateOfMind: [TimedValue] = []
    }

    static func healthDemo(today: Date, now: Date, calendar: Calendar) -> HealthDemo {
        var demo = HealthDemo()
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        // MARK: Sleep: 42 nights. Night `offset` ends on the morning of day(offset).

        // The six nights before last night (7-night average 7 h 05 with last night).
        let recent: [Int: Double] = [-6: 415, -5: 445, -4: 400, -3: 430, -2: 455, -1: 398]
        // Short nights (under 6 h) before four of the five elevated afternoons, in
        // the last five weeks but outside the four weeks "usual" uses.
        let short: Set<Int> = [-29, -31, -33, -34]
        func minutes(_ offset: Int) -> Double {
            if let value = recent[offset] { return value }
            if short.contains(offset) { return 335 }
            // Days -28…-7: nine at 7 h 15, four at 7 h 20, nine at 7 h 35, so the median is 7 h 20.
            let index = -offset - 7
            return index < 9 ? 435 : index < 13 ? 440 : 455
        }
        func night(_ offset: Int, bedtime: Date, segments: [(SleepSample.Stage, Double)]) {
            var start = bedtime
            for (stage, length) in segments {
                let end = start.addingTimeInterval(length * 60)
                demo.sleep.append(SleepSample(start: start, end: end, stage: stage, isWatch: true))
                start = end
            }
        }
        for offset in -41 ... -1 {
            // Usual bedtime 23:08 (±10 min), so last night's 23:48 is 40 min later.
            let wobble = [0.0, 10, -10][(-offset) % 3]
            let bedtime = day(offset).addingTimeInterval((-52 + wobble) * 60)
            let asleep = minutes(offset)
            night(offset, bedtime: bedtime, segments: [(.deep, asleep * 0.18), (.core, asleep * 0.30), (.rem, asleep * 0.22), (.core, asleep * 0.30)])
        }
        // Last night: deep 1 h 18, core 4 h 20, REM 1 h 34, awake 6 min.
        night(0, bedtime: day(0).addingTimeInterval(-12 * 60), segments: [(.deep, 78), (.core, 130), (.awake, 6), (.rem, 94), (.core, 130)])

        // MARK: Heart: 61 days. Resting averages 58 with a usual range of 56–61.

        let resting: [Double] = [55, 57, 58, 59, 61, 58, 56, 61, 57, 58]
        let overnight: [Double] = [50, 55, 52, 56, 53, 51, 54]
        let elevatedAfternoons: Set<Int> = short.union([-32])
        for offset in -60 ... -1 {
            demo.restingHeartRate.append(DailyValue(day: day(offset), value: resting[(-offset) % resting.count]))
            demo.walkingHeartRate.append(DailyValue(day: day(offset), value: [94, 97, 95, 98, 96][(-offset) % 5]))
            demo.heartRateVariability += [
                TimedValue(date: day(offset).addingTimeInterval(3 * 3600), value: overnight[(-offset) % overnight.count]),
                TimedValue(date: day(offset).addingTimeInterval(9 * 3600), value: 52),
                TimedValue(date: day(offset).addingTimeInterval(14 * 3600), value: elevatedAfternoons.contains(offset) ? 40 : 52),
            ]
        }
        demo.restingHeartRate.append(DailyValue(day: today, value: 58))
        demo.walkingHeartRate.append(DailyValue(day: today, value: 96))
        // Today: 47 ms overnight, calm morning, elevated afternoon, calm so far this evening.
        demo.heartRateVariability += [
            TimedValue(date: today.addingTimeInterval(3 * 3600), value: 47),
            TimedValue(date: today.addingTimeInterval(9 * 3600), value: 52),
            TimedValue(date: today.addingTimeInterval(14 * 3600), value: 42),
            TimedValue(date: today.addingTimeInterval(18 * 3600 + 20 * 60), value: 50),
        ]

        // Today's hourly range, 00:00 to now (49–142 bpm).
        let hours: [(Double, Double)] = [
            (52, 56), (50, 54), (49, 53), (50, 54), (50, 54), (51, 55), (54, 62), (68, 104), (72, 118), (75, 96),
            (74, 90), (76, 99), (80, 142), (78, 120), (74, 92), (72, 88), (70, 86), (73, 94), (76, 101),
        ]
        let currentHour = calendar.component(.hour, from: now)
        for (hour, range) in hours.enumerated() where hour <= currentHour {
            demo.heartRateToday.append(HourlyRange(start: today.addingTimeInterval(Double(hour) * 3600), min: range.0, max: range.1))
        }

        // A State of Mind entry made in the Health app at lunch.
        demo.stateOfMind = [TimedValue(date: today.addingTimeInterval(12.5 * 3600), value: 0.4)]
        return demo
    }
}
#endif
