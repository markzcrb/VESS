import Foundation
import Testing
@testable import VESS

@Suite("Habits: suggestions, new rules and counts")
struct HabitSuggestionTests {
    private let calendar = TestClock.utc

    @Test("The category follows the name until it's picked")
    func guess() {
        #expect(HabitRules.guessCategory("Stretch for 10 minutes") == .movement)
        #expect(HabitRules.guessCategory("Vitamin D") == .supplements)
        #expect(HabitRules.guessCategory("No screens in bed") == .sleep)
        #expect(HabitRules.guessCategory("3 portions of veg") == .nutrition)
        #expect(HabitRules.guessCategory("Call a friend") == .other)
    }

    @Test("Sleep, mindful minutes, fibre and supplements complete from the day's data")
    func autoRules() {
        var data = HabitRules.DayData()
        data.sleepMinutes = 432
        data.mindfulMinutes = 10
        data.fiberGrams = 26
        data.supplementsDue = 2
        data.supplementsTaken = 2
        #expect(HabitRules.isAutoDone(.sleep(minutes: 420), data: data))
        #expect(!HabitRules.isAutoDone(.sleep(minutes: 480), data: data))
        #expect(HabitRules.isAutoDone(.mindfulMinutes(10), data: data))
        #expect(HabitRules.isAutoDone(.fiber(grams: 25), data: data))
        #expect(HabitRules.isAutoDone(.supplementsTaken, data: data))
        data.supplementsTaken = 1
        #expect(!HabitRules.isAutoDone(.supplementsTaken, data: data))
        data.supplementsDue = 0
        #expect(!HabitRules.isAutoDone(.supplementsTaken, data: data), "Nothing due isn't done")
    }

    @Test("No caffeine after 14:00: done only once 14:00 has passed with none since")
    func caffeineCutoff() {
        var today = HabitRules.DayData()
        today.currentHour = 11
        today.latestCaffeineHour = 9
        #expect(!HabitRules.isAutoDone(.noCaffeineAfter(hour: 14), data: today), "Too early to say")
        today.currentHour = 18
        #expect(HabitRules.isAutoDone(.noCaffeineAfter(hour: 14), data: today))
        today.latestCaffeineHour = 15
        #expect(!HabitRules.isAutoDone(.noCaffeineAfter(hour: 14), data: today))
        var pastDay = HabitRules.DayData()
        pastDay.latestCaffeineHour = nil
        #expect(HabitRules.isAutoDone(.noCaffeineAfter(hour: 14), data: pastDay))
    }

    @Test("\"3× a day\": done at the third tick")
    func timesPerDay() throws {
        let day = try TestClock.date(2026, 10, 6, 12)
        let veg = Habit(id: UUID(), name: "3 portions of veg", schedule: .daily, category: .nutrition, reminder: nil, auto: nil,
                        createdAt: day, timesPerDay: 3)
        let ticks = (0..<2).map { _ in HabitCheck(id: UUID(), habitID: veg.id, day: day) }
        let log = HabitRules.Log(checks: ticks, calendar: calendar)
        #expect(HabitRules.checkCount(veg, on: day, log: log, calendar: calendar) == 2)
        #expect(!HabitRules.isDone(veg, on: day, log: log, calendar: calendar))
        let three = HabitRules.Log(checks: ticks + [HabitCheck(id: UUID(), habitID: veg.id, day: day)], calendar: calendar)
        #expect(HabitRules.isDone(veg, on: day, log: three, calendar: calendar))
    }
}
