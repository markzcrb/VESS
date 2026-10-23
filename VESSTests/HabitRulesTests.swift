import Foundation
import Testing
@testable import VESS

@Suite("Habits")
struct HabitRulesTests {
    /// Weeks start on Monday, like the reference.
    private let calendar: Calendar = {
        var calendar = TestClock.utc
        calendar.firstWeekday = 2
        return calendar
    }()

    /// 5 October 2026 is a Monday.
    private func day(_ dayOfMonth: Int, _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
        try TestClock.date(2026, 10, dayOfMonth, hour, minute, calendar: calendar)
    }

    private func habit(_ schedule: HabitSchedule, auto: HabitAutoRule? = nil, reminder: DateComponents? = nil, created: Date? = nil) throws -> Habit {
        Habit(id: UUID(), name: "Test", schedule: schedule, category: .other, reminder: reminder, auto: auto,
              createdAt: try created ?? TestClock.date(2026, 9, 1, calendar: calendar))
    }

    private func checks(_ habit: Habit, _ days: [Int]) throws -> [HabitCheck] {
        try days.map { HabitCheck(id: UUID(), habitID: habit.id, day: try day($0)) }
    }

    @Test("Daily every day, Weekdays Monday to Friday, chosen days only on those days")
    func schedules() throws {
        let weekdays = try habit(.weekdays)
        #expect(HabitRules.isScheduled(weekdays, on: try day(9), calendar: calendar))    // Friday
        #expect(!HabitRules.isScheduled(weekdays, on: try day(10), calendar: calendar))  // Saturday
        let chosen = try habit(.days([2, 4]))                                             // Monday, Wednesday
        #expect(HabitRules.isScheduled(chosen, on: try day(7), calendar: calendar))
        #expect(!HabitRules.isScheduled(chosen, on: try day(8), calendar: calendar))
        #expect(HabitRules.isScheduled(try habit(.daily), on: try day(11), calendar: calendar))
    }

    @Test("Water reaches the target; protein at breakfast is 25 g or more; steps need Health data")
    func autoRules() {
        typealias Data = HabitRules.DayData
        #expect(HabitRules.isAutoDone(.waterTarget, data: Data(hydrationMilliliters: 2200, waterTargetMilliliters: 2200)))
        #expect(!HabitRules.isAutoDone(.waterTarget, data: Data(hydrationMilliliters: 2199, waterTargetMilliliters: 2200)))
        #expect(!HabitRules.isAutoDone(.waterTarget, data: Data(hydrationMilliliters: 500, waterTargetMilliliters: 0)))
        #expect(HabitRules.isAutoDone(.proteinAtBreakfast, data: Data(breakfastProteinGrams: 25)))
        #expect(!HabitRules.isAutoDone(.proteinAtBreakfast, data: Data(breakfastProteinGrams: 24.9)))
        #expect(HabitRules.isAutoDone(.steps(8000), data: Data(steps: 8000)))
        #expect(!HabitRules.isAutoDone(.steps(8000), data: Data(steps: 7999)))
        #expect(!HabitRules.isAutoDone(.steps(8000), data: Data(steps: nil)))
        #expect(!HabitRules.isAutoDone(.steps(8000), data: nil))
    }

    @Test("Auto-tracked habits read the day's data, not ticks")
    func autoDone() throws {
        let water = try habit(.daily, auto: .waterTarget)
        let log = HabitRules.Log(
            checks: try checks(water, [6]),
            data: [try day(7): .init(hydrationMilliliters: 2300, waterTargetMilliliters: 2200)],
            calendar: calendar
        )
        #expect(HabitRules.isDone(water, on: try day(7, 20), log: log, calendar: calendar))
        #expect(!HabitRules.isDone(water, on: try day(6), log: log, calendar: calendar))
    }

    @Test("Twice a week: counted in the locale's week, complete once reached, past days count only when done")
    func timesPerWeek() throws {
        let fish = try habit(.timesPerWeek(2))
        let log = HabitRules.Log(checks: try checks(fish, [4, 6]), calendar: calendar)  // Sunday 4 is last week
        let thursday = try day(8)
        #expect(HabitRules.weekCount(fish, through: thursday, log: log, calendar: calendar) == 1)
        #expect(!HabitRules.isComplete(fish, on: thursday, log: log, calendar: calendar))
        #expect(HabitRules.isListed(fish, on: thursday, today: thursday, log: log, calendar: calendar))
        // Monday without it isn't on that day's list, so the share isn't lowered.
        #expect(!HabitRules.isListed(fish, on: try day(5), today: thursday, log: log, calendar: calendar))
        #expect(HabitRules.isListed(fish, on: try day(6), today: thursday, log: log, calendar: calendar))
        #expect(HabitRules.marks(fish, today: thursday, log: log, calendar: calendar) == [.notDone, .done, .notDone, .open, .future, .future, .future])

        let twice = HabitRules.Log(checks: try checks(fish, [6, 7]), calendar: calendar)
        #expect(HabitRules.isComplete(fish, on: thursday, log: twice, calendar: calendar))
        #expect(HabitRules.marks(fish, today: thursday, log: twice, calendar: calendar)[3] == .future)

        // With weeks starting on Sunday, Sunday 4 counts toward this week.
        var sunday = calendar
        sunday.firstWeekday = 1
        #expect(HabitRules.weekCount(fish, through: thursday, log: log, calendar: sunday) == 2)
    }

    @Test("Dots: done, empty for past scheduled days, open today, faint for later and unscheduled days")
    func marks() throws {
        let walk = try habit(.weekdays)
        let log = HabitRules.Log(checks: try checks(walk, [6, 7]), calendar: calendar)
        #expect(HabitRules.marks(walk, today: try day(8), log: log, calendar: calendar) == [.notDone, .done, .done, .open, .future, .future, .future])
        let checked = HabitRules.Log(checks: try checks(walk, [8]), calendar: calendar)
        #expect(HabitRules.marks(walk, today: try day(8), log: checked, calendar: calendar)[3] == .done)
        // Added on Wednesday: earlier days are faint.
        let new = try habit(.daily, created: try day(7, 9))
        #expect(HabitRules.marks(new, today: try day(8), log: HabitRules.Log(calendar: calendar), calendar: calendar).prefix(2) == [.future, .future])
    }

    @Test("Today's list and share, with habits added later left out")
    func status() throws {
        let a = try habit(.daily)
        let b = try habit(.daily)
        let later = try habit(.daily, created: try day(9))
        let weekend = try habit(.days([1, 7]))
        let log = HabitRules.Log(checks: try checks(a, [8]), calendar: calendar)
        let status = HabitRules.status([a, b, later, weekend], on: try day(8), today: try day(8), log: log, calendar: calendar)
        #expect(status == HabitRules.DayStatus(listed: 2, done: 1))
        #expect(status.share == 0.5)
        #expect(HabitRules.status([weekend], on: try day(8), today: try day(8), log: log, calendar: calendar).share == nil)
    }

    @Test("Four levels: none, up to a third, up to two thirds, more")
    func levels() {
        #expect(HabitRules.level(nil) == 0)
        #expect(HabitRules.level(0) == 0)
        #expect(HabitRules.level(0.25) == 1)
        #expect(HabitRules.level(1.0 / 3) == 1)
        #expect(HabitRules.level(0.5) == 2)
        #expect(HabitRules.level(2.0 / 3) == 2)
        #expect(HabitRules.level(0.8) == 3)
        #expect(HabitRules.level(1) == 3)
    }

    @Test("The grid is four weeks of seven, ending this week; later days are empty")
    func grid() throws {
        let a = try habit(.daily)
        let log = HabitRules.Log(checks: try checks(a, [8]), calendar: calendar)
        let grid = HabitRules.grid([a], today: try day(8), log: log, calendar: calendar)
        #expect(grid.count == 4)
        #expect(grid.allSatisfy { $0.count == 7 })
        #expect(grid[3] == [0, 0, 0, 3, nil, nil, nil])
    }

    @Test("Recent: days before today with more than half the list done")
    func recent() throws {
        let a = try habit(.daily)
        let b = try habit(.daily)
        let log = HabitRules.Log(checks: try checks(a, [2, 3, 4, 7, 8]) + checks(b, [2, 3, 7]), calendar: calendar)
        let recent = HabitRules.recent([a, b], today: try day(8), log: log, calendar: calendar)
        #expect(recent == HabitRules.Recent(mostDone: 3, days: 7))
    }

    @Test("Reminders at the habit's time on its days; not when done, not in quiet hours, not after the week's count")
    func reminders() throws {
        let morning = DateComponents(hour: 8, minute: 0)
        let walk = try habit(.weekdays, reminder: morning)
        let late = try habit(.daily, reminder: DateComponents(hour: 22, minute: 30))
        let fish = try habit(.timesPerWeek(2), reminder: DateComponents(hour: 18, minute: 0))
        let silent = try habit(.daily)
        let log = HabitRules.Log(checks: try checks(walk, [8]) + checks(fish, [6, 7]), calendar: calendar)
        let now = try day(8, 7, 0)   // Thursday 07:00

        let plan = HabitRules.reminders([walk, late, fish, silent], log: log, now: now, calendar: calendar)
        let walkDays = plan.filter { $0.habitID == walk.id }.map { calendar.component(.day, from: $0.date) }
        #expect(walkDays == [9, 12, 13, 14])          // not today (done), not the weekend
        #expect(plan.allSatisfy { $0.habitID != late.id })   // 22:30 is in quiet hours
        // Fish reached two this week, so it starts again next Monday.
        #expect(plan.filter { $0.habitID == fish.id }.map { calendar.component(.day, from: $0.date) } == [12, 13, 14])
        #expect(plan.first?.id.hasPrefix(HabitRules.idPrefix) == true)
    }
}
