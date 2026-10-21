import Foundation
import Testing
@testable import VESS

@Suite("Workout energy")
struct WorkoutEnergyTests {
    @Test("MET × kg × hours: a 30-minute moderate walk at 78.4 kg is about 137 kcal")
    func walk() {
        #expect(WorkoutEnergy.estimate(type: .walking, effort: .moderate, minutes: 30, weightKilograms: 78.4) == 137)
    }

    @Test("Harder effort never gives less energy, for every type")
    func effortOrder() {
        for type in WorkoutType.allCases {
            let easy = WorkoutEnergy.met(for: type, effort: .easy)
            let moderate = WorkoutEnergy.met(for: type, effort: .moderate)
            let hard = WorkoutEnergy.met(for: type, effort: .hard)
            #expect(easy <= moderate && moderate <= hard, "\(type)")
        }
    }

    @Test("No estimate without a weight or a duration")
    func missingInputs() {
        #expect(WorkoutEnergy.estimate(type: .running, effort: .hard, minutes: 30, weightKilograms: 0) == nil)
        #expect(WorkoutEnergy.estimate(type: .running, effort: .hard, minutes: 0, weightKilograms: 70) == nil)
    }

    @Test("Workouts saved by earlier builds still decode, as entered")
    func oldPayload() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Run","type":"running","durationMinutes":30,"exercises":[]}"#
        let workout = try JSONDecoder().decode(Workout.self, from: Data(json.utf8))
        #expect(workout.source == nil)
        #expect(!workout.isRecorded)
        #expect(workout.effort == nil)
    }
}

@Suite("Activity trends")
struct ActivityTrendsTests {
    private let calendar = TestClock.utc

    /// `total` steps spread evenly over 08:00–20:00 (12 hours).
    private func day(_ date: Date, total: Double) -> [HourlyValue] {
        let start = calendar.startOfDay(for: date)
        return (8..<20).map { HourlyValue(start: start.addingTimeInterval(Double($0) * 3600), value: total / 12) }
    }

    @Test("A day's total, and up to a clock time with the current hour in proportion")
    func totals() throws {
        let date = try TestClock.date(2026, 10, 6)
        let values = day(date, total: 1_200)
        #expect(ActivityTrends.total(values, on: date, calendar: calendar) == 1_200)
        // 08:00–14:00 full (6 × 100) plus half of 14:00.
        let cutoff = try TestClock.date(2026, 10, 6, 14, 30)
        #expect(ActivityTrends.total(values, on: date, upTo: cutoff, calendar: calendar) == 650)
        let dayBefore = try TestClock.date(2026, 10, 5)
        #expect(ActivityTrends.total(values, on: dayBefore, calendar: calendar) == nil, "No samples is no data, not zero")
    }

    @Test("A typical weekday is the median of the last four, up to the same time; all four are needed")
    func typical() throws {
        let now = try TestClock.date(2026, 10, 6, 20, 0)
        var values: [HourlyValue] = []
        for (week, total) in [(1, 7_600.0), (2, 8_400), (3, 7_900), (4, 8_100)] {
            values += day(try #require(calendar.date(byAdding: .day, value: -7 * week, to: now)), total: total)
        }
        #expect(ActivityTrends.typical(values, at: now, calendar: calendar) == 8_000)

        let threeWeeks = values.filter { $0.start > (calendar.date(byAdding: .day, value: -22, to: now) ?? now) }
        #expect(ActivityTrends.typical(threeWeeks, at: now, calendar: calendar) == nil)
    }

    @Test("Within ±10 % is about the same")
    func compare() {
        #expect(ActivityTrends.compare(1_090, with: 1_000) == .aboutSame)
        #expect(ActivityTrends.compare(911, with: 1_000) == .aboutSame)
        #expect(ActivityTrends.compare(1_120, with: 1_000) == .above)
        #expect(ActivityTrends.compare(880, with: 1_000) == .below)
    }

    @Test("Week against the week before needs every earlier day")
    func period() throws {
        let today = try TestClock.date(2026, 10, 6)
        var values: [HourlyValue] = []
        for offset in -13...0 {
            values += day(try #require(calendar.date(byAdding: .day, value: offset, to: today)), total: offset > -7 ? 9_000 : 7_000)
        }
        #expect(ActivityTrends.periodComparison(values, days: 7, endingOn: today, calendar: calendar) == .above)

        let gap = values.filter { !calendar.isDate($0.start, inSameDayAs: calendar.date(byAdding: .day, value: -10, to: today) ?? today) }
        #expect(ActivityTrends.periodComparison(gap, days: 7, endingOn: today, calendar: calendar) == nil)
    }

    @Test("Weekly pattern: weekends against weekdays and the quietest day, only with four full weeks")
    func pattern() throws {
        let today = try TestClock.date(2026, 10, 6)
        var values: [HourlyValue] = []
        for offset in -28 ... -1 {
            let date = try #require(calendar.date(byAdding: .day, value: offset, to: today))
            let weekday = calendar.component(.weekday, from: date)
            let total: Double = [1, 7].contains(weekday) ? 11_000 : (weekday == 5 ? 5_000 : 8_000)
            values += day(date, total: total)
        }
        let pattern = try #require(ActivityTrends.weeklyPattern(values, before: today, calendar: calendar))
        #expect(pattern.weekendsBusiest == true)
        #expect(pattern.quietestWeekday == 5, "Thursday")

        #expect(ActivityTrends.weeklyPattern(Array(values.dropFirst(12)), before: today, calendar: calendar) == nil)
    }

    @Test("Most active hour and workout types by frequency")
    func dayAndWorkouts() throws {
        let date = try TestClock.date(2026, 10, 6)
        let start = calendar.startOfDay(for: date)
        let values = [HourlyValue(start: start.addingTimeInterval(9 * 3600), value: 300), HourlyValue(start: start.addingTimeInterval(12 * 3600), value: 1_400)]
        #expect(ActivityTrends.mostActiveHour(values, on: date, calendar: calendar) == start.addingTimeInterval(12 * 3600))

        func workout(_ type: WorkoutType, _ hour: Int) -> Workout {
            Workout(id: UUID(), name: "", type: type, durationMinutes: 30, exercises: [], scheduledDate: nil,
                    completedAt: start.addingTimeInterval(Double(hour) * 3600), notes: nil, templateID: nil)
        }
        let types = ActivityTrends.typesByFrequency([workout(.walking, 8), workout(.strength, 9), workout(.walking, 10)])
        #expect(types.map(\.type) == [.walking, .strength])
    }
}

@Suite("Activity demo data")
struct ActivityDemoTests {
    @Test("The demo week matches DATA.md, and today is above a typical Tuesday by 16:20")
    func demoWeek() throws {
        let calendar = TestClock.utc
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let health = MockData(now: now, calendar: calendar).health
        let week = ActivityTrends.dailyTotals(health.hourlySteps, days: 7, endingOn: now, calendar: calendar).compactMap(\.value)
        #expect(week == [7_840, 5_210, 8_930, 11_240, 4_380, 9_120, 6_420])
        #expect(ActivityTrends.total(health.hourlyActiveEnergy, on: now, calendar: calendar) == 412)

        let typical = try #require(ActivityTrends.typical(health.hourlySteps, at: health.updatedAt, calendar: calendar))
        let comparison = ActivityTrends.compare(Double(health.steps), with: typical)
        #expect(comparison == .above)
        let allRecorded = health.workouts.allSatisfy(\.isRecorded)
        #expect(allRecorded)
    }
}
