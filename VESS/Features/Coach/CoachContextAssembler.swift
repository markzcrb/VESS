import Foundation

/// Gathers the builder's input from what's on this iPhone. The rule itself
/// (`CoachContextBuilder`) is pure and tested; this only reads.
enum CoachContextAssembler {
    static func context(store: LocalStore, health: HealthSnapshot?, shareCycle: Bool, now: Date, calendar: Calendar) -> CoachContext? {
        guard let profile = store.profile else { return nil }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let weekStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        // 30 days for the charts' series.
        let monthStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today

        let habits = store.habits
        let log = HabitLogLoader.log(store: store, health: health, from: weekStart, through: now, calendar: calendar)
        let listed = habits.filter { HabitRules.isListed($0, on: now, today: now, log: log, calendar: calendar) }
        let done = listed.filter { HabitRules.isComplete($0, on: now, log: log, calendar: calendar) }

        // Habit-days done over the 7 days before today.
        var habitDays = 0, habitDaysDone = 0
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for habit in habits where HabitRules.isListed(habit, on: day, today: now, log: log, calendar: calendar) {
                habitDays += 1
                if HabitRules.isComplete(habit, on: day, log: log, calendar: calendar) { habitDaysDone += 1 }
            }
        }

        let useSoon = store.inventory
            .filter { ExpirationStatus(expirationDate: $0.expirationDate, now: now, calendar: calendar).needsAttention }
            .sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
            .map(\.name)

        let supplements = SupplementRules.today(store.supplements, logs: store.supplementLogs(on: now, calendar: calendar), on: now, calendar: calendar)
        let taken = supplements.items.filter { $0.takenAt != nil }.map(\.supplement.name)
        let due = supplements.items.filter { $0.takenAt == nil && SupplementRules.isScheduled($0.supplement, on: now, calendar: calendar) }.map(\.supplement.name)

        var cycle: CoachContextInput.CycleShare?
        if profile.isCycleTrackingOn, shareCycle {
            let summary = CyclePrediction.summary(store.cycleDays, today: now, calendar: calendar)
            cycle = .init(
                cycleDay: summary.cycleDay,
                nextPeriod: summary.estimate.map { DateInterval(start: $0.windowStart, end: max($0.windowEnd, $0.windowStart)) }
            )
        }

        let input = CoachContextInput(
            now: now,
            calendar: calendar,
            name: profile.name,
            targets: profile.nutritionTargets,
            waterTargetMilliliters: profile.waterTargetMilliliters,
            stepsTarget: profile.dailyStepsTarget,
            entries: store.foodEntries(from: monthStart, to: tomorrow),
            drinks: store.hydrationLogs(from: monthStart, to: tomorrow),
            hourlySteps: health?.hourlySteps,
            habitsDone: done.map(\.name),
            habitsOpen: listed.filter { habit in !done.contains { $0.id == habit.id } }.map(\.name),
            workouts: store.workouts + (health?.workouts ?? []),
            supplementsTaken: taken,
            supplementsDue: due,
            cycle: cycle,
            pregnant: profile.pregnant,
            preferences: profile.preferences,
            allergens: profile.allergies,
            health: health,
            sleepTargetMinutes: profile.dailySleepTargetMinutes,
            weightKilograms: profile.weightKilograms,
            weightSavedAt: profile.updatedAt,
            goalWeightKilograms: profile.goalWeightKilograms,
            bmi: BodyRules.showsBMI(profile: profile, now: now, calendar: calendar) ? BodyRules.bmi(profile: profile, health: health?.latestWeight) : nil,
            habitCompletion7d: habitDays > 0 ? Double(habitDaysDone) / Double(habitDays) : nil,
            plannedMealsToday: store.plannedMeals(from: today, to: tomorrow),
            pantryUseSoon: useSoon
        )
        return CoachContextBuilder.build(input)
    }
}
