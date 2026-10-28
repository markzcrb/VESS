import Foundation

// Every other metric Coach can be asked about (item 4a), already added up
// on the device: totals for today, the 7 days before, and 30-day series
// for charts. `null` where there's no data, never a guessed 0.

nonisolated extension CoachContext {
    /// A metric's day totals: today, the 7 days before (oldest first), their
    /// total and the average over the days with data.
    struct Series: Codable, Equatable, Sendable {
        var today: Int?
        var byDay: [DayValue]
        var total7d: Int?
        var avgKnownDays: Int?
    }

    struct Caffeine: Codable, Equatable, Sendable {
        var todayMg: Int
        var limitMg: Int
        var byDay: [DayValue]
    }

    struct DrinkCount: Codable, Equatable, Sendable {
        var type: String
        var count: Int
        var ml: Int
    }

    struct WorkoutTotals: Codable, Equatable, Sendable {
        var todayCount: Int
        var todayMinutes: Int
        var last7dCount: Int
        var last7dMinutes: Int
    }

    struct Sleep: Codable, Equatable, Sendable {
        struct Night: Codable, Equatable, Sendable {
            var date: String
            var asleepMin: Int
            var bedtime: String
            var wake: String
            /// Minutes per stage; absent without stage data.
            var coreMin: Int?
            var deepMin: Int?
            var remMin: Int?
            var awakeMin: Int?
        }

        var lastNight: Night?
        var avg7NightsMin: Int?
        var targetMin: Int
        var byNight: [DayValue]
    }

    /// Resting heart rate (bpm) or HRV (ms): today against the usual range.
    struct Vital: Codable, Equatable, Sendable {
        var today: Int?
        var usualLow: Int?
        var usualHigh: Int?
        var byDay: [DayValue]
    }

    struct Stress: Codable, Equatable, Sendable {
        /// calm, elevated or high; `nil` while the baseline builds.
        var today: String?
        /// morning, afternoon, evening → level, so far today.
        var parts: [String: String]
        /// Days of baseline so far, when fewer than 14.
        var baselineDays: Int?
        var note: String
    }

    struct Body: Codable, Equatable, Sendable {
        var weightKg: Double?
        var weightDate: String?
        /// Absent when BMI is hidden (under 18, pregnant).
        var bmi: Double?
        var goalWeightKg: Double?
    }

    /// 30 days, oldest first, today last. Dropped first when the summary
    /// is too long.
    struct Month: Codable, Equatable, Sendable {
        var steps: [DayValue]?
        var energy: [DayValue]
        var protein: [DayValue]
        var water: [DayValue]
        var weightKg: [DayValueDecimal]
        var sleepMin: [DayValue]?
    }

    /// A day value with one decimal (weight), null without data.
    struct DayValueDecimal: Codable, Equatable, Sendable {
        var date: String
        var value: Double?

        enum CodingKeys: String, CodingKey { case date, value }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(date, forKey: .date)
            try container.encode(value, forKey: .value)
        }
    }
}

nonisolated extension CoachContextBuilder {
    /// Adds every other metric to `context`.
    static func addMetrics(_ context: inout CoachContext, input: CoachContextInput) {
        let calendar = input.calendar
        let today = calendar.startOfDay(for: input.now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let week = (1...7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let month = (0..<30).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }

        let entries = Dictionary(grouping: input.entries.filter { $0.loggedAt <= input.now }) { calendar.startOfDay(for: $0.loggedAt) }
        let drinks = Dictionary(grouping: input.drinks.filter { $0.loggedAt <= input.now }) { calendar.startOfDay(for: $0.loggedAt) }
        func food(_ day: Date) -> NutritionFacts? { entries[day].map { $0.map(\.nutrition).total } }

        func series(today todayValue: Double?, _ value: (Date) -> Double?) -> CoachContext.Series {
            let values = week.map { (day: $0, value: value($0)) }
            let known = values.compactMap(\.value)
            return .init(
                today: todayValue.map(round),
                byDay: values.map { .init(date: dayString($0.day, calendar), value: $0.value.map(round)) },
                total7d: known.isEmpty ? nil : round(known.reduce(0, +)),
                avgKnownDays: known.isEmpty ? nil : round(known.reduce(0, +) / Double(known.count))
            )
        }
        func values(_ days: [Date], _ value: (Date) -> Double?) -> [CoachContext.DayValue] {
            days.map { .init(date: dayString($0, calendar), value: value($0).map(round)) }
        }

        // Food beyond energy and protein.
        let todayFood = food(today)
        context.carbs = series(today: todayFood?.carbohydrateGrams ?? 0) { food($0)?.carbohydrateGrams }
        context.fat = series(today: todayFood?.fatGrams ?? 0) { food($0)?.fatGrams }
        context.fiber = series(today: todayFood?.fiberGrams) { food($0)?.fiberGrams }
        context.sugar = series(today: todayFood?.sugarGrams) { food($0)?.sugarGrams }

        // Drinks: caffeine against the limit, and today's by type.
        let caffeineToday = CaffeineModel.total(drinks[today] ?? [], on: today, calendar: calendar)
        context.caffeine = .init(
            todayMg: round(caffeineToday), limitMg: round(CaffeineModel.dailyLimitMilligrams),
            byDay: values(week) { day in drinks[day].map { CaffeineModel.total($0, on: day, calendar: calendar) } }
        )
        context.drinksToday = Dictionary(grouping: drinks[today] ?? [], by: \.drinkType.rawValue)
            .map { .init(type: $0.key, count: $0.value.count, ml: round($0.value.reduce(0) { $0 + $1.volumeMilliliters })) }
            .sorted { $0.type < $1.type }

        // Workouts, logged and from Apple Health.
        let done = input.workouts.compactMap { workout -> (Date, Int)? in
            guard let end = workout.completedAt, end <= input.now else { return nil }
            return (end, workout.durationMinutes ?? 0)
        }
        let todayWorkouts = done.filter { $0.0 >= today && $0.0 < tomorrow }
        let weekWorkouts = done.filter { $0.0 >= (week.first ?? today) && $0.0 < today }
        context.workouts = .init(
            todayCount: todayWorkouts.count, todayMinutes: todayWorkouts.reduce(0) { $0 + $1.1 },
            last7dCount: weekWorkouts.count, last7dMinutes: weekWorkouts.reduce(0) { $0 + $1.1 }
        )

        // Apple Health.
        if let health = input.health {
            context.activeEnergy = series(today: health.activeEnergyKilocalories) {
                ActivityTrends.total(health.hourlyActiveEnergy, on: $0, calendar: calendar)
            }

            let nights = SleepRules.nights(health.sleep, calendar: calendar)
            let lastNight = SleepRules.lastNight(nights, now: input.now, calendar: calendar)
            let weekNights = SleepRules.week(nights, now: input.now, calendar: calendar).compactMap(\.minutes)
            context.sleep = .init(
                lastNight: lastNight.map { night in
                    .init(
                        date: dayString(night.day, calendar), asleepMin: round(night.asleepMinutes),
                        bedtime: clockString(night.start, calendar), wake: clockString(night.end, calendar),
                        coreMin: night.stages[.core].map(round), deepMin: night.stages[.deep].map(round),
                        remMin: night.stages[.rem].map(round), awakeMin: night.stages[.awake].map(round)
                    )
                },
                avg7NightsMin: weekNights.isEmpty ? nil : round(weekNights.reduce(0, +) / Double(weekNights.count)),
                targetMin: input.sleepTargetMinutes,
                byNight: values(week) { day in nights.first { $0.day == day }?.asleepMinutes }
            )

            func vital(_ daily: [DailyValue]) -> CoachContext.Vital? {
                guard !daily.isEmpty else { return nil }
                let usual = HeartRules.usualRange(daily, before: input.now, calendar: calendar)
                return .init(
                    today: HeartRules.value(on: input.now, daily, calendar: calendar).map(round),
                    usualLow: usual.map { round($0.lowerBound) }, usualHigh: usual.map { round($0.upperBound) },
                    byDay: values(week) { HeartRules.value(on: $0, daily, calendar: calendar) }
                )
            }
            context.restingHr = vital(health.restingHeartRate)
            context.hrv = vital(StressRules.overnightHRV(health.heartRateVariability, calendar: calendar))

            switch StressRules.estimate(hrvSamples: health.heartRateVariability, restingHeartRate: health.restingHeartRate,
                                        now: input.now, calendar: calendar) {
            case .estimate(let level, let parts):
                context.stress = .init(
                    today: level.rawValue,
                    parts: Dictionary(uniqueKeysWithValues: parts.map { ("\($0.key)", $0.value.rawValue) }),
                    baselineDays: nil, note: stressNote
                )
            case .building(let days):
                context.stress = .init(today: nil, parts: [:], baselineDays: days, note: stressNote)
            case nil:
                break
            }
        }

        // Body.
        let latest = input.health?.latestWeight
        let weight = latest?.kilograms ?? input.weightKilograms
        context.body = .init(
            weightKg: weight.map(oneDecimal),
            weightDate: (latest?.measuredAt ?? input.weightSavedAt).map { dayString($0, calendar) },
            bmi: input.bmi.map(oneDecimal),
            goalWeightKg: input.goalWeightKilograms.map(oneDecimal)
        )

        context.habitsCompletion7dPct = input.habitCompletion7d.map { round($0 * 100) }
        context.plannedMealsToday = input.plannedMealsToday
            .filter { calendar.isDate($0.day, inSameDayAs: input.now) }
            .sorted { MealType.dayOrder.firstIndex(of: $0.mealType) ?? 0 < MealType.dayOrder.firstIndex(of: $1.mealType) ?? 0 }
            .map { .init(meal: $0.mealType.rawValue, name: $0.name, kcal: round($0.nutrition.calories)) }
        context.pantryUseSoon = input.pantryUseSoon

        // 30 days for charts.
        var weights = input.health?.weights ?? []
        if let saved = input.weightSavedAt, let kilograms = input.weightKilograms,
           !weights.contains(where: { calendar.isDate($0.measuredAt, inSameDayAs: saved) }) {
            weights.append(BodyMassSample(kilograms: kilograms, measuredAt: saved))
        }
        let nights = input.health.map { SleepRules.nights($0.sleep, calendar: calendar) }
        context.last30Days = .init(
            steps: input.hourlySteps.map { hourly in values(month) { ActivityTrends.total(hourly, on: $0, calendar: calendar) } },
            energy: values(month) { day in
                guard entries[day] != nil || drinks[day] != nil else { return nil }
                return (food(day)?.calories ?? 0) + (drinks[day] ?? []).reduce(0) { $0 + $1.energyCalories }
            },
            protein: values(month) { food($0)?.proteinGrams },
            water: values(month) { day in drinks[day].map { $0.reduce(0) { $0 + $1.hydrationMilliliters } } },
            weightKg: month.map { day in
                .init(date: dayString(day, calendar),
                      value: weights.last { calendar.isDate($0.measuredAt, inSameDayAs: day) }.map { oneDecimal($0.kilograms) })
            },
            sleepMin: nights.map { nights in values(month) { day in nights.first { $0.day == day }?.asleepMinutes } }
        )
    }

    static let stressNote = "Estimate from heart rate variability and resting heart rate, not a diagnosis."

    private static func round(_ value: Double) -> Int { Int(value.rounded()) }
    private static func oneDecimal(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    fileprivate static func dayString(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    fileprivate static func clockString(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
