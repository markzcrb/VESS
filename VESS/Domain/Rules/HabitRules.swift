import Foundation

/// Habits (14): what's on the list each day, what's done, the week's dots,
/// the share of the list done, and reminders. Pure and deterministic.
///
/// - Daily, Weekdays (Monday–Friday) and chosen days are on the list on
///   their days. "N times a week" habits are on today's list every day; on
///   past days they count only on the days they were done, so a day without
///   one never lowers the share.
/// - An N-times-a-week habit is complete for the day once it's done that day
///   or the week's count is reached. The week is the locale's week.
/// - Auto-tracked habits complete themselves: water when the day's
///   hydration reaches the target; protein at breakfast at
///   `breakfastProteinGrams` or more; steps when Apple Health reaches the
///   habit's target. Without Health data steps are simply not done.
/// - No streaks and nothing "missed": a past day without it is an empty dot.
nonisolated enum HabitRules {
    static let breakfastProteinGrams: Double = 25
    static let daysAhead = 7
    static let idPrefix = "habit."

    /// What the auto rules read for one day.
    nonisolated struct DayData: Equatable, Sendable {
        var hydrationMilliliters: Double = 0
        var waterTargetMilliliters: Double = 0
        var breakfastProteinGrams: Double = 0
        /// `nil` without Apple Health data.
        var steps: Int?
    }

    /// Hand ticks and auto-rule data, keyed by the start of each day.
    nonisolated struct Log: Sendable {
        var checks: [UUID: Set<Date>]
        var data: [Date: DayData]

        init(checks: [HabitCheck] = [], data: [Date: DayData] = [:], calendar: Calendar) {
            var byHabit: [UUID: Set<Date>] = [:]
            for check in checks {
                byHabit[check.habitID, default: []].insert(calendar.startOfDay(for: check.day))
            }
            self.checks = byHabit
            self.data = Dictionary(data.map { (calendar.startOfDay(for: $0.key), $0.value) }, uniquingKeysWith: { _, new in new })
        }
    }

    /// One dot in the week row.
    nonisolated enum Mark: Equatable, Sendable {
        case done, notDone, open, future
    }

    nonisolated struct DayStatus: Equatable, Sendable {
        let listed: Int
        let done: Int
        /// `nil` when nothing was on the list.
        var share: Double? { listed > 0 ? Double(done) / Double(listed) : nil }
    }

    // MARK: Schedule

    static func isScheduled(_ habit: Habit, on day: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        switch habit.schedule {
        case .daily, .timesPerWeek: return true
        case .weekdays: return (2...6).contains(weekday)
        case .days(let days): return days.contains(weekday)
        }
    }

    /// The seven days of the locale's week holding `day`.
    static func week(containing day: Date, calendar: Calendar) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    // MARK: Done

    static func isAutoDone(_ rule: HabitAutoRule, data: DayData?) -> Bool {
        guard let data else { return false }
        switch rule {
        case .waterTarget:
            return data.waterTargetMilliliters > 0 && data.hydrationMilliliters >= data.waterTargetMilliliters
        case .proteinAtBreakfast:
            return data.breakfastProteinGrams >= breakfastProteinGrams
        case .steps(let target):
            guard let steps = data.steps else { return false }
            return steps >= target
        }
    }

    /// Done on that day: ticked, or its auto rule met.
    static func isDone(_ habit: Habit, on day: Date, log: Log, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        if let auto = habit.auto { return isAutoDone(auto, data: log.data[start]) }
        return log.checks[habit.id]?.contains(start) ?? false
    }

    /// Days done in `day`'s week, up to and including `day`.
    static func weekCount(_ habit: Habit, through day: Date, log: Log, calendar: Calendar) -> Int {
        let end = calendar.startOfDay(for: day)
        return week(containing: day, calendar: calendar).filter { $0 <= end && isDone(habit, on: $0, log: log, calendar: calendar) }.count
    }

    /// The check mark for `day`.
    static func isComplete(_ habit: Habit, on day: Date, log: Log, calendar: Calendar) -> Bool {
        if case .timesPerWeek(let times) = habit.schedule {
            return isDone(habit, on: day, log: log, calendar: calendar) || weekCount(habit, through: day, log: log, calendar: calendar) >= times
        }
        return isDone(habit, on: day, log: log, calendar: calendar)
    }

    /// Whether the habit is on `day`'s list (not before it was added).
    static func isListed(_ habit: Habit, on day: Date, today: Date, log: Log, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard calendar.startOfDay(for: habit.createdAt) <= start, start <= calendar.startOfDay(for: today) else { return false }
        if case .timesPerWeek = habit.schedule, start < calendar.startOfDay(for: today) {
            return isDone(habit, on: day, log: log, calendar: calendar)
        }
        return isScheduled(habit, on: day, calendar: calendar)
    }

    static func status(_ habits: [Habit], on day: Date, today: Date, log: Log, calendar: Calendar) -> DayStatus {
        let listed = habits.filter { isListed($0, on: day, today: today, log: log, calendar: calendar) }
        return DayStatus(listed: listed.count, done: listed.filter { isComplete($0, on: day, log: log, calendar: calendar) }.count)
    }

    // MARK: Display

    /// The habit's seven dots for `today`'s week.
    static func marks(_ habit: Habit, today: Date, log: Log, calendar: Calendar) -> [Mark] {
        let todayStart = calendar.startOfDay(for: today)
        let created = calendar.startOfDay(for: habit.createdAt)
        return week(containing: today, calendar: calendar).map { day in
            if day > todayStart || day < created { return .future }
            let done = isDone(habit, on: day, log: log, calendar: calendar)
            if case .timesPerWeek = habit.schedule {
                if done { return .done }
                if day == todayStart { return isComplete(habit, on: day, log: log, calendar: calendar) ? .future : .open }
                return .notDone
            }
            guard isScheduled(habit, on: day, calendar: calendar) else { return .future }
            if done { return .done }
            return day == todayStart ? .open : .notDone
        }
    }

    /// Four greyscale levels of the share done: 0 (nothing, or nothing on
    /// the list), 1 (up to a third), 2 (up to two thirds), 3 (more).
    static func level(_ share: Double?) -> Int {
        guard let share, share > 0 else { return 0 }
        if share <= 1.0 / 3 { return 1 }
        if share <= 2.0 / 3 { return 2 }
        return 3
    }

    /// The last 28 days in whole weeks, ending with `today`'s week: four
    /// rows of seven, oldest first. Days after today are `nil`.
    static func grid(_ habits: [Habit], today: Date, log: Log, calendar: Calendar) -> [[Int?]] {
        let thisWeek = week(containing: today, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        return (0..<4).reversed().map { weeksBack in
            thisWeek.compactMap { calendar.date(byAdding: .day, value: -7 * weeksBack, to: $0) }.map { day in
                day > todayStart ? nil : level(status(habits, on: day, today: today, log: log, calendar: calendar).share)
            }
        }
    }

    /// Of the last seven days before today that had a list, how many had
    /// more than half of it done.
    nonisolated struct Recent: Equatable, Sendable {
        let mostDone: Int
        let days: Int
    }

    static func recent(_ habits: [Habit], today: Date, log: Log, calendar: Calendar) -> Recent {
        let statuses = (1...7).compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: today)) }
            .map { status(habits, on: $0, today: today, log: log, calendar: calendar) }
            .filter { $0.listed > 0 }
        return Recent(mostDone: statuses.filter { ($0.share ?? 0) > 0.5 }.count, days: statuses.count)
    }

    // MARK: Reminders

    nonisolated struct Reminder: Equatable, Sendable {
        let id: String
        let habitID: UUID
        let date: Date
    }

    /// At the habit's time on its days, for the next `days` days; not once
    /// it's complete today, not after an N-times-a-week count is reached,
    /// and never in quiet hours (`MealReminders`).
    static func reminders(_ habits: [Habit], log: Log, now: Date, calendar: Calendar, days: Int = daysAhead) -> [Reminder] {
        let today = calendar.startOfDay(for: now)
        return habits.flatMap { habit -> [Reminder] in
            guard let time = habit.reminder else { return [] }
            return (0..<days).compactMap { offset -> Reminder? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let date = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day),
                      date > now, !MealReminders.isQuiet(date, calendar: calendar),
                      isScheduled(habit, on: day, calendar: calendar),
                      !isComplete(habit, on: day, log: log, calendar: calendar)
                else { return nil }
                let parts = calendar.dateComponents([.year, .month, .day], from: day)
                let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                return Reminder(id: "\(idPrefix)\(habit.id.uuidString).\(stamp)", habitID: habit.id, date: date)
            }
        }
    }
}
