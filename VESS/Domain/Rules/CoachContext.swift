import Foundation

/// The summary Coach gets with a question: targets, today's totals, the
/// last 7 days' averages, today's meals, habits, workouts and supplements,
/// and cycle data only when tracking and sharing are both on. Plain values,
/// whole numbers, no IDs. "What Coach sees" shows exactly this JSON.
nonisolated struct CoachContext: Codable, Equatable, Sendable {
    struct Targets: Codable, Equatable, Sendable {
        var kcal: Int
        var proteinG: Int
        var carbsG: Int
        var fatG: Int
        var waterMl: Int
        var steps: Int
    }

    struct Totals: Codable, Equatable, Sendable {
        var kcal: Int
        var proteinG: Int
        var carbsG: Int
        var fatG: Int
        var waterMl: Int
        /// `nil` without Apple Health.
        var steps: Int?
    }

    struct Week: Codable, Equatable, Sendable {
        /// Days with meals among the 7 before today.
        var daysLogged: Int
        var avgKcal: Int?
        var avgProteinG: Int?
        var avgWaterMl: Int?
        var avgSteps: Int?
    }

    struct Meal: Codable, Equatable, Sendable {
        var meal: String
        var name: String
        var kcal: Int
    }

    struct Workout: Codable, Equatable, Sendable {
        var date: String
        var type: String
        var minutes: Int?
        var kcal: Int?
    }

    struct Checklist: Codable, Equatable, Sendable {
        var done: [String]
        var open: [String]
    }

    struct Cycle: Codable, Equatable, Sendable {
        var cycleDay: Int?
        /// The estimated window for the next period, if there is one.
        var nextPeriodFrom: String?
        var nextPeriodTo: String?
        var note: String
    }

    var date: String
    var time: String
    var name: String?
    var targets: Targets
    var today: Totals
    var last7Days: Week
    var mealsToday: [Meal]
    var habitsToday: Checklist
    var workoutsLast7Days: [Workout]
    var supplementsToday: Checklist
    var cycle: Cycle?
    /// Set (true) only when the user has switched on Pregnant in You › Body;
    /// absent otherwise. The Coach must not suggest losing weight.
    var pregnant: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case date, time, name, targets, today, cycle, pregnant
        case last7Days = "last_7_days"
        case mealsToday = "meals_today"
        case habitsToday = "habits_today"
        case workoutsLast7Days = "workouts_last_7_days"
        case supplementsToday = "supplements_today"
    }
}

/// What the builder reads. Kept plain so the rule is testable.
nonisolated struct CoachContextInput: Sendable {
    var now: Date
    var calendar: Calendar
    var name: String?
    var targets: NutritionTargets
    var waterTargetMilliliters: Double
    var stepsTarget: Int
    /// Food entries covering at least today and the 7 days before.
    var entries: [FoodLogEntry]
    var drinks: [HydrationLog]
    /// `nil` without Apple Health.
    var hourlySteps: [HourlyValue]?
    var habitsDone: [String]
    var habitsOpen: [String]
    var workouts: [Workout]
    var supplementsTaken: [String]
    var supplementsDue: [String]
    /// Only set when cycle tracking AND "Share cycle with Coach" are on.
    var cycle: CycleShare?
    /// You › Body › Pregnant.
    var pregnant = false

    struct CycleShare: Sendable {
        var cycleDay: Int?
        var nextPeriod: DateInterval?
    }
}

nonisolated enum CoachContextBuilder {
    /// The JSON stays under this, so the server never has to cut it.
    static let maxBytes = 6 * 1024

    static func build(_ input: CoachContextInput) -> CoachContext {
        let calendar = input.calendar
        let today = calendar.startOfDay(for: input.now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let weekStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        let todayEntries = input.entries.filter { $0.loggedAt >= today && $0.loggedAt < tomorrow && $0.loggedAt <= input.now }
        let todayDrinks = input.drinks.filter { $0.loggedAt >= today && $0.loggedAt < tomorrow && $0.loggedAt <= input.now }
        let food = todayEntries.map(\.nutrition).total

        // The 7 days before today: averages over the days with meals.
        let weekEntries = input.entries.filter { $0.loggedAt >= weekStart && $0.loggedAt < today }
        let byDay = Dictionary(grouping: weekEntries) { calendar.startOfDay(for: $0.loggedAt) }
        let weekDrinks = input.drinks.filter { $0.loggedAt >= weekStart && $0.loggedAt < today }
        let drinksByDay = Dictionary(grouping: weekDrinks) { calendar.startOfDay(for: $0.loggedAt) }
        let dayKcal = byDay.map { day, entries in
            entries.map(\.nutrition).total.calories + (drinksByDay[day] ?? []).reduce(0) { $0 + $1.energyCalories }
        }
        let dayProtein = byDay.values.map { $0.map(\.nutrition).total.proteinGrams }
        let dayWater = drinksByDay.values.map { $0.reduce(0) { $0 + $1.hydrationMilliliters } }

        let steps = input.hourlySteps.flatMap { ActivityTrends.total($0, on: input.now, upTo: input.now, calendar: calendar) }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let weekSteps = input.hourlySteps.flatMap {
            ActivityTrends.average(ActivityTrends.dailyTotals($0, days: 7, endingOn: yesterday, calendar: calendar))
        }

        let meals = todayEntries.sorted { $0.loggedAt < $1.loggedAt }.map {
            CoachContext.Meal(meal: $0.mealType.rawValue, name: $0.foodName, kcal: round($0.nutrition.calories))
        }
        let workouts = input.workouts
            .compactMap { workout -> (Date, Workout)? in
                guard let end = workout.completedAt, end >= weekStart, end <= input.now else { return nil }
                return (end, workout)
            }
            .sorted { $0.0 > $1.0 }
            .map { end, workout in
                CoachContext.Workout(
                    date: day(end, calendar: calendar),
                    type: workout.type.rawValue,
                    minutes: workout.durationMinutes,
                    kcal: workout.activeEnergyKilocalories.map(round)
                )
            }

        let context = CoachContext(
            date: day(input.now, calendar: calendar),
            time: clock(input.now, calendar: calendar),
            name: input.name?.isEmpty == false ? input.name : nil,
            targets: .init(
                kcal: round(input.targets.calories), proteinG: round(input.targets.proteinGrams),
                carbsG: round(input.targets.carbohydrateGrams), fatG: round(input.targets.fatGrams),
                waterMl: round(input.waterTargetMilliliters), steps: input.stepsTarget
            ),
            today: .init(
                kcal: round(food.calories + todayDrinks.reduce(0) { $0 + $1.energyCalories }),
                proteinG: round(food.proteinGrams), carbsG: round(food.carbohydrateGrams), fatG: round(food.fatGrams),
                waterMl: round(todayDrinks.reduce(0) { $0 + $1.hydrationMilliliters }),
                steps: steps.map(round)
            ),
            last7Days: .init(
                daysLogged: byDay.count,
                avgKcal: average(dayKcal).map(round),
                avgProteinG: average(dayProtein).map(round),
                avgWaterMl: average(dayWater).map(round),
                avgSteps: weekSteps.map(round)
            ),
            mealsToday: meals,
            habitsToday: .init(done: input.habitsDone, open: input.habitsOpen),
            workoutsLast7Days: workouts,
            supplementsToday: .init(done: input.supplementsTaken, open: input.supplementsDue),
            cycle: input.cycle.map { share in
                .init(
                    cycleDay: share.cycleDay,
                    nextPeriodFrom: share.nextPeriod.map { day($0.start, calendar: calendar) },
                    nextPeriodTo: share.nextPeriod.map { day($0.end, calendar: calendar) },
                    note: "Estimate from logged periods, not a medical prediction."
                )
            },
            pregnant: input.pregnant ? true : nil
        )
        return fitted(context)
    }

    /// Compact JSON with snake_case keys, sorted for a stable result.
    static func json(_ context: CoachContext) -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(context)) ?? Data("{}".utf8)
    }

    /// The same JSON, indented, for "What Coach sees".
    static func readableJSON(_ context: CoachContext) -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return (try? encoder.encode(context)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Drops detail before totals when the summary is too long: workouts,
    /// then meals, then long names.
    static func fitted(_ context: CoachContext) -> CoachContext {
        var context = context
        while json(context).count > maxBytes {
            if context.workoutsLast7Days.count > 3 {
                context.workoutsLast7Days.removeLast()
            } else if context.mealsToday.count > 5 {
                context.mealsToday.removeFirst()
            } else if context.mealsToday.contains(where: { $0.name.count > 40 }) {
                context.mealsToday = context.mealsToday.map { var meal = $0; meal.name = String(meal.name.prefix(40)); return meal }
            } else if !context.workoutsLast7Days.isEmpty {
                context.workoutsLast7Days.removeLast()
            } else if !context.mealsToday.isEmpty {
                context.mealsToday.removeFirst()
            } else if context.habitsToday.done.count + context.habitsToday.open.count > 0 {
                context.habitsToday = .init(done: Array(context.habitsToday.done.prefix(5)), open: Array(context.habitsToday.open.prefix(5)))
                if json(context).count > maxBytes { context.habitsToday = .init(done: [], open: []) }
            } else {
                context.supplementsToday = .init(done: [], open: [])
                break
            }
        }
        return context
    }

    private static func round(_ value: Double) -> Int { Int(value.rounded()) }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
