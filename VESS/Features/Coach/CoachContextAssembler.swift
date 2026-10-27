import Foundation

/// Gathers the builder's input from what's on this iPhone. The rule itself
/// (`CoachContextBuilder`) is pure and tested; this only reads.
enum CoachContextAssembler {
    static func context(store: LocalStore, health: HealthSnapshot?, shareCycle: Bool, now: Date, calendar: Calendar) -> CoachContext? {
        guard let profile = store.profile else { return nil }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let weekStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        let habits = store.habits
        let log = HabitLogLoader.log(store: store, health: health, from: weekStart, through: now, calendar: calendar)
        let listed = habits.filter { HabitRules.isListed($0, on: now, today: now, log: log, calendar: calendar) }
        let done = listed.filter { HabitRules.isComplete($0, on: now, log: log, calendar: calendar) }

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
            entries: store.foodEntries(from: weekStart, to: tomorrow),
            drinks: store.hydrationLogs(from: weekStart, to: tomorrow),
            hourlySteps: health?.hourlySteps,
            habitsDone: done.map(\.name),
            habitsOpen: listed.filter { habit in !done.contains { $0.id == habit.id } }.map(\.name),
            workouts: store.workouts + (health?.workouts ?? []),
            supplementsTaken: taken,
            supplementsDue: due,
            cycle: cycle,
            pregnant: profile.pregnant,
            preferences: profile.preferences,
            allergens: profile.allergies
        )
        return CoachContextBuilder.build(input)
    }
}
