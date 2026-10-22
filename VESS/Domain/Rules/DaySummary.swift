import Foundation

/// The Day Word: a single qualitative word for how the day is going.
/// VESS deliberately has no numeric daily score.
nonisolated enum DayWord: Hashable, Sendable {
    /// Nothing logged yet.
    case freshStart
    /// Eating roughly in step with the time of day.
    case onTrack
    /// Logged less than usual for this time of day.
    case lightSoFar
    /// Calories reached (or passed) the target.
    case fullDay
}

/// Everything Today and Nutrition need to describe a day, derived from logs.
/// Pure and deterministic: the same inputs always produce the same summary.
nonisolated struct DaySummary: Sendable {
    /// The day's food, plus the kcal of alcoholic drinks in `calories`.
    let consumed: NutritionFacts
    /// kcal from alcoholic drinks, included in `consumed.calories`.
    let alcoholCalories: Double
    let targets: NutritionTargets
    let hydration: HydrationProgress
    let dayWord: DayWord
    /// Share of the day's eating window that has passed (0 at 07:00, 1 at 21:00,
    /// always 1 for past days).
    let expectedPace: Double
    let isProteinBehind: Bool
    let isWaterBehind: Bool

    /// Pace is never taken as less than a quarter of the day, so an early
    /// breakfast isn't compared with almost nothing (Energy and Macros).
    static let minimumPace = 0.25
    /// Below this share of the expected pace, a measure counts as "behind".
    static let behindThreshold = 0.75
    /// At or above this share of the calorie target, the day is "full".
    static let fullDayThreshold = 0.95

    init(
        entries: [FoodLogEntry],
        hydrationLogs: [HydrationLog],
        targets: NutritionTargets,
        waterTargetMilliliters: Double,
        day: Date,
        now: Date,
        calendar: Calendar
    ) {
        let dayEntries = entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
        let alcoholCalories = hydrationLogs
            .filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
            .reduce(0) { $0 + $1.energyCalories }
        var consumed = dayEntries.totalNutrition
        consumed.calories += alcoholCalories
        let hydration = HydrationProgress(
            logs: hydrationLogs,
            targetMilliliters: waterTargetMilliliters,
            day: day,
            calendar: calendar
        )
        let pace = Self.expectedPace(day: day, now: now, calendar: calendar)

        self.consumed = consumed
        self.alcoholCalories = alcoholCalories
        self.targets = targets
        self.hydration = hydration
        self.expectedPace = pace

        let calorieFraction = Self.fraction(consumed.calories, of: targets.calories)
        let proteinFraction = Self.fraction(consumed.proteinGrams, of: targets.proteinGrams)
        let paceFloor = pace * Self.behindThreshold

        // Early in the day nothing counts as behind.
        self.isProteinBehind = pace >= 0.25 && proteinFraction < paceFloor
        self.isWaterBehind = pace >= 0.25 && hydration.fractionComplete < paceFloor

        if dayEntries.isEmpty && hydration.consumedMilliliters == 0 {
            dayWord = .freshStart
        } else if calorieFraction >= Self.fullDayThreshold {
            dayWord = .fullDay
        } else if calorieFraction >= paceFloor {
            dayWord = .onTrack
        } else {
            dayWord = .lightSoFar
        }
    }

    /// Target minus consumed. Negative when above target.
    var caloriesRemaining: Double { targets.calories - consumed.calories }

    /// kcal from food only. Fuel uses this, so drinking never raises it.
    var foodCalories: Double { consumed.calories - alcoholCalories }

    /// The day's eating window runs 07:00–21:00. Past days are complete.
    static func expectedPace(day: Date, now: Date, calendar: Calendar) -> Double {
        let startOfDay = calendar.startOfDay(for: day)
        if startOfDay < calendar.startOfDay(for: now) { return 1 }
        if startOfDay > calendar.startOfDay(for: now) { return 0 }
        let hours = now.timeIntervalSince(startOfDay) / 3600
        return min(max((hours - 7) / 14, 0), 1)
    }

    private static func fraction(_ value: Double, of target: Double) -> Double {
        target > 0 ? value / target : 0
    }
}

// MARK: - Meals

nonisolated extension MealType {
    /// Display order through the day.
    static let dayOrder: [MealType] = [.breakfast, .lunch, .snack, .dinner]

    /// The main meals VESS suggests adding; snacks are never nagged about.
    static let mainMeals: [MealType] = [.breakfast, .lunch, .dinner]

    /// The last hour (24 h) at which suggesting this meal still makes sense.
    var suggestionEndHour: Int {
        switch self {
        case .breakfast: 11
        case .lunch: 16
        case .snack: 21
        case .dinner: 24
        }
    }

    /// The meal to suggest next on Today: the first main meal not yet logged
    /// whose time hasn't passed. `nil` when there's nothing sensible to suggest.
    static func nextSuggestion(logged: Set<MealType>, now: Date, calendar: Calendar) -> MealType? {
        let hour = calendar.component(.hour, from: now)
        return mainMeals.first { !logged.contains($0) && hour < $0.suggestionEndHour }
    }

    /// The meal a new entry most likely belongs to, given the time of day.
    static func likely(at date: Date, calendar: Calendar) -> MealType {
        switch calendar.component(.hour, from: date) {
        case ..<11: .breakfast
        case ..<15: .lunch
        case ..<18: .snack
        default: .dinner
        }
    }
}

nonisolated extension Sequence where Element == FoodLogEntry {
    /// Median time of day this meal is logged, from at least `minimumDays`
    /// distinct days of history. Used for "Usually around 19:30".
    func usualTime(for mealType: MealType, calendar: Calendar, minimumDays: Int = 3) -> DateComponents? {
        // First entry of the meal on each day.
        var firstMinuteByDay: [Date: Int] = [:]
        for entry in self where entry.mealType == mealType {
            let day = calendar.startOfDay(for: entry.loggedAt)
            let parts = calendar.dateComponents([.hour, .minute], from: entry.loggedAt)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            firstMinuteByDay[day] = Swift.min(firstMinuteByDay[day] ?? .max, minutes)
        }
        guard firstMinuteByDay.count >= minimumDays else { return nil }

        let sorted = firstMinuteByDay.values.sorted()
        let median = sorted[sorted.count / 2]
        // Round to the nearest 15 minutes so it reads as a habit, not a timestamp.
        let rounded = Int((Double(median) / 15).rounded()) * 15
        return DateComponents(hour: (rounded / 60) % 24, minute: rounded % 60)
    }
}
