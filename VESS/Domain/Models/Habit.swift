import Foundation

/// A habit (14, 16): something the user wants to do on a schedule. Either
/// ticked by hand or tracked from data VESS already has. Stored only on
/// this iPhone. No streaks: a day without it is simply a day without it.
nonisolated struct Habit: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var schedule: HabitSchedule
    var category: HabitCategory
    /// Reminder time (hour and minute); `nil` is off, the default.
    var reminder: DateComponents?
    /// Set for habits that complete themselves; `nil` is ticked by hand.
    var auto: HabitAutoRule?
    let createdAt: Date
}

nonisolated enum HabitSchedule: Codable, Hashable, Sendable {
    case daily
    /// Monday to Friday.
    case weekdays
    /// Chosen days, as `Calendar` weekdays (1 = Sunday … 7 = Saturday).
    case days(Set<Int>)
    /// Any days, this many times a week (the locale's week).
    case timesPerWeek(Int)
}

nonisolated enum HabitCategory: String, Codable, CaseIterable, Sendable {
    case nutrition, movement, supplements, sleep, other
}

/// How an auto-tracked habit completes itself (`HabitRules`).
nonisolated enum HabitAutoRule: Codable, Hashable, Sendable {
    /// The day's hydration reaches the water target in the profile.
    case waterTarget
    /// Breakfast has at least `HabitRules.breakfastProteinGrams` of protein.
    case proteinAtBreakfast
    /// Apple Health steps reach this many.
    case steps(Int)
}

/// A day a hand-ticked habit was done.
nonisolated struct HabitCheck: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let habitID: UUID
    /// The start of the day.
    let day: Date
}
