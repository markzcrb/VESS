import Foundation

/// Meal reminders (PRODUCT-LOGIC.md #12, decided 2026-10-21): on-device and
/// opt-in. One reminder per main meal, 30 minutes after its usual time, only
/// if nothing is logged for it that day, and never in quiet hours (22:00 to
/// 07:00 unless the user changed them).
/// A meal without a usual time (fewer than three days of history) gets none.
///
/// Local notifications can't check the log when they fire, so the app plans
/// the next `daysAhead` days and plans again whenever the log changes.
/// Pure and deterministic.
nonisolated enum MealReminders {
    static let delay: TimeInterval = 30 * 60
    static let daysAhead = 7
    /// Identifier prefix, so the scheduler only replaces its own requests.
    static let idPrefix = "meal."

    nonisolated struct Reminder: Equatable, Sendable {
        let id: String
        let meal: MealType
        let date: Date
    }

    static func isQuiet(_ date: Date, quiet: QuietHours = .standard, calendar: Calendar) -> Bool {
        quiet.contains(date, calendar: calendar)
    }

    /// - Parameters:
    ///   - history: past entries, for usual times.
    ///   - logged: everything logged from today on, so a logged meal's
    ///     reminder is left out.
    static func plan(history: [FoodLogEntry], logged: [FoodLogEntry], now: Date, calendar: Calendar, days: Int = daysAhead,
                     quiet: QuietHours = .standard) -> [Reminder] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).flatMap { offset -> [Reminder] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return MealType.mainMeals.compactMap { meal in
                guard let usual = history.usualTime(for: meal, calendar: calendar),
                      let time = calendar.date(bySettingHour: usual.hour ?? 0, minute: usual.minute ?? 0, second: 0, of: day)
                else { return nil }
                let date = time.addingTimeInterval(delay)
                let isLogged = logged.contains { $0.mealType == meal && calendar.isDate($0.loggedAt, inSameDayAs: day) }
                guard date > now, !quiet.contains(date, calendar: calendar), !isLogged else { return nil }
                let parts = calendar.dateComponents([.year, .month, .day], from: day)
                let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                return Reminder(id: "\(idPrefix)\(meal.rawValue).\(stamp)", meal: meal, date: date)
            }
        }
    }
}

/// No reminders between `start` and `end` (minutes after midnight). The
/// window may run past midnight (22:00–07:00); start equal to end means no
/// quiet hours. Applies to every reminder VESS schedules.
nonisolated struct QuietHours: Codable, Hashable, Sendable {
    var start: Int
    var end: Int

    static let standard = QuietHours(start: 22 * 60, end: 7 * 60)

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start == end { return false }
        return start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    /// The first time at or after `date` outside quiet hours.
    func firstAllowed(atOrAfter date: Date, calendar: Calendar) -> Date {
        guard contains(date, calendar: calendar) else { return date }
        let day = calendar.startOfDay(for: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        // The end is later today, or (past midnight in a 22–07 window) tomorrow.
        let endToday = calendar.date(byAdding: .minute, value: end, to: day) ?? date
        if minute < end { return endToday }
        return calendar.date(byAdding: .day, value: 1, to: endToday) ?? endToday
    }
}
