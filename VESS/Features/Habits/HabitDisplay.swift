import SwiftUI

// Names, colours and data loading for habits.

extension HabitCategory {
    var title: LocalizedStringResource {
        switch self {
        case .nutrition: "Nutrition"
        case .movement: "Movement"
        case .supplements: "Supplements"
        case .sleep: "Sleep"
        case .other: "Other"
        }
    }
}

extension Habit {
    /// Done dots: water and protein use their metric hue, other nutrition
    /// habits energy, movement activity; everything else is neutral.
    var hue: Color {
        switch auto {
        case .waterTarget: return VESSColor.water
        case .proteinAtBreakfast: return VESSColor.protein
        case .steps: return VESSColor.activity
        case .sleep, .mindfulMinutes: return VESSColor.sleep
        case .noCaffeineAfter, .fiber: return VESSColor.carbs
        case .supplementsTaken, nil: break
        }
        switch category {
        case .nutrition: return VESSColor.calories
        case .movement: return VESSColor.activity
        case .supplements, .sleep, .other: return VESSColor.text
        }
    }
}

extension HabitSchedule {
    /// "Daily", "Weekdays", "Mon · Wed", "2 times a week".
    func title(calendar: Calendar) -> Text {
        switch self {
        case .daily: return Text("Daily")
        case .weekdays: return Text("Weekdays")
        case .days(let days):
            let symbols = calendar.shortStandaloneWeekdaySymbols
            let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }.filter { days.contains($0) }
            return Text(verbatim: ordered.map { symbols[$0 - 1] }.joined(separator: " · "))
        case .timesPerWeek(let times):
            return Text("^[\(times) time](inflect: true) a week")
        }
    }
}

extension HabitRules.Mark {
    var dot: VESSHabitRow.Dot {
        switch self {
        case .done: .done
        case .notDone: .notDone
        case .open: .open
        case .future: .future
        }
    }
}

/// Builds the rules' log from what VESS already stores: ticks, the day's
/// drinks against the water target, breakfast protein, and Apple Health
/// steps (hourly history, today's total).
enum HabitLogLoader {
    static func log(store: LocalStore, health: HealthSnapshot?, from start: Date, through end: Date, calendar: Calendar) -> HabitRules.Log {
        let first = calendar.startOfDay(for: start)
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let target = store.profile?.waterTargetMilliliters ?? 0

        var data: [Date: HabitRules.DayData] = [:]
        var day = first
        while day < last {
            data[day] = HabitRules.DayData(waterTargetMilliliters: target)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? last
        }
        for drink in store.hydrationLogs(from: first, to: last) {
            let key = calendar.startOfDay(for: drink.loggedAt)
            data[key]?.hydrationMilliliters += drink.hydrationMilliliters
            if drink.caffeineMilligrams >= 1 {
                let hour = calendar.component(.hour, from: drink.loggedAt)
                let latest = data[key]?.latestCaffeineHour ?? -1
                data[key]?.latestCaffeineHour = max(latest, hour)
            }
        }
        for entry in store.foodEntries(from: first, to: last) {
            let key = calendar.startOfDay(for: entry.loggedAt)
            if entry.mealType == .breakfast { data[key]?.breakfastProteinGrams += entry.nutrition.proteinGrams }
            data[key]?.fiberGrams += entry.nutrition.fiberGrams ?? 0
        }
        // Supplements due and taken each day.
        for key in data.keys {
            let summary = SupplementRules.today(store.supplements, logs: store.supplementLogs(on: key, calendar: calendar), on: key, calendar: calendar)
            let due = summary.items.filter { SupplementRules.isScheduled($0.supplement, on: key, calendar: calendar) }
            data[key]?.supplementsDue = due.count
            data[key]?.supplementsTaken = due.filter { $0.takenAt != nil }.count
        }
        // Today's hour, for "no caffeine after 14:00".
        let now = AppClock.now
        if data[calendar.startOfDay(for: now)] != nil {
            data[calendar.startOfDay(for: now)]?.currentHour = calendar.component(.hour, from: now)
        }
        if let health {
            for hour in health.hourlySteps {
                let key = calendar.startOfDay(for: hour.start)
                let sum = (data[key]?.steps ?? 0) + Int(hour.value)
                data[key]?.steps = sum
            }
            // Today's total is the latest reading.
            let today = calendar.startOfDay(for: health.updatedAt)
            if data[today] != nil {
                data[today]?.steps = health.steps
                data[today]?.mindfulMinutes = health.mindfulMinutesToday
            }
            for night in SleepRules.nights(health.sleep, calendar: calendar) where data[night.day] != nil {
                data[night.day]?.sleepMinutes = night.asleepMinutes
            }
        }
        return HabitRules.Log(checks: store.habitChecks(from: first, to: last), data: data, calendar: calendar)
    }
}

enum HabitCopy {
    static let noStreaks: LocalizedStringResource = "No streaks to protect. Miss a day and simply pick it up again."
    static let gridNote: LocalizedStringResource = "Each square is a day. Stronger means more of the list was done."

    /// Under the ring and on the Today row: "2 left this evening",
    /// "All done today".
    static func remaining(_ status: HabitRules.DayStatus, now: Date, calendar: Calendar) -> Text {
        let left = status.listed - status.done
        if status.listed == 0 { return Text("Nothing on today's list") }
        if left == 0 { return Text("All done today") }
        return calendar.component(.hour, from: now) >= 17 ? Text("\(left) left this evening") : Text("\(left) left today")
    }
}
