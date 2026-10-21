import Foundation

/// Meal reminders (PRODUCT-LOGIC.md #12, decided 2026-10-21): on-device and
/// opt-in. One reminder per main meal, 30 minutes after its usual time, only
/// if nothing is logged for it that day, and never between 22:00 and 07:00.
/// A meal without a usual time (fewer than three days of history) gets none.
///
/// Local notifications can't check the log when they fire, so the app plans
/// the next `daysAhead` days and plans again whenever the log changes.
/// Pure and deterministic.
nonisolated enum MealReminders {
    static let delay: TimeInterval = 30 * 60
    static let quietStartHour = 22
    static let quietEndHour = 7
    static let daysAhead = 7
    /// Identifier prefix, so the scheduler only replaces its own requests.
    static let idPrefix = "meal."

    nonisolated struct Reminder: Equatable, Sendable {
        let id: String
        let meal: MealType
        let date: Date
    }

    static func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= quietStartHour || hour < quietEndHour
    }

    /// - Parameters:
    ///   - history: past entries, for usual times.
    ///   - logged: everything logged from today on, so a logged meal's
    ///     reminder is left out.
    static func plan(history: [FoodLogEntry], logged: [FoodLogEntry], now: Date, calendar: Calendar, days: Int = daysAhead) -> [Reminder] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).flatMap { offset -> [Reminder] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            return MealType.mainMeals.compactMap { meal in
                guard let usual = history.usualTime(for: meal, calendar: calendar),
                      let time = calendar.date(bySettingHour: usual.hour ?? 0, minute: usual.minute ?? 0, second: 0, of: day)
                else { return nil }
                let date = time.addingTimeInterval(delay)
                let isLogged = logged.contains { $0.mealType == meal && calendar.isDate($0.loggedAt, inSameDayAs: day) }
                guard date > now, !isQuiet(date, calendar: calendar), !isLogged else { return nil }
                let parts = calendar.dateComponents([.year, .month, .day], from: day)
                let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                return Reminder(id: "\(idPrefix)\(meal.rawValue).\(stamp)", meal: meal, date: date)
            }
        }
    }
}
