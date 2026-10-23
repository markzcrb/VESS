#if DEBUG
import Foundation

extension MockData {
    /// SAMPLE habits for captures (`-habitsDemo`), like reference 14: six
    /// habits added five weeks ago, with ticks over the last four weeks in a
    /// fixed pattern. Today: Vitamin D, the walk and fish are ticked;
    /// screens off isn't. Protein at breakfast and water track themselves
    /// from the sample log.
    static func seedHabits(into store: LocalStore, now: Date, calendar: Calendar) throws {
        let today = calendar.startOfDay(for: now)
        let created = calendar.date(byAdding: .day, value: -35, to: today) ?? today
        func habit(_ name: String, _ schedule: HabitSchedule, _ category: HabitCategory, reminder: Int? = nil, auto: HabitAutoRule? = nil) -> Habit {
            Habit(id: UUID(), name: name, schedule: schedule, category: category,
                  reminder: reminder.map { DateComponents(hour: $0, minute: 0) }, auto: auto, createdAt: created)
        }
        let target = store.profile?.waterTargetMilliliters ?? 2200
        let protein = habit("Protein at breakfast", .daily, .nutrition, auto: .proteinAtBreakfast)
        let vitaminD = habit("Vitamin D", .daily, .supplements, reminder: 8)
        let walk = habit("Walk after lunch", .weekdays, .movement, reminder: 13)
        let fish = habit("Fish twice a week", .timesPerWeek(2), .nutrition)
        let water = habit("Water \(VESSFormat.liters(fromMilliliters: target)) L", .daily, .nutrition, auto: .waterTarget)
        let screens = habit("Screens off by 23:00", .daily, .sleep)
        for item in [protein, vitaminD, walk, fish, water, screens] { try store.save(item) }

        // Ticks for the last 28 days, a fixed pattern so captures repeat.
        for offset in 1...28 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if offset % 6 != 0 { try store.setHabit(vitaminD.id, done: true, on: day, calendar: calendar) }
            if HabitRules.isScheduled(walk, on: day, calendar: calendar), offset % 4 != 1 {
                try store.setHabit(walk.id, done: true, on: day, calendar: calendar)
            }
            if offset % 3 == 0 { try store.setHabit(screens.id, done: true, on: day, calendar: calendar) }
            if offset % 7 == 2 || offset % 7 == 5 { try store.setHabit(fish.id, done: true, on: day, calendar: calendar) }
        }
        for item in [vitaminD, walk, fish] where HabitRules.isScheduled(item, on: today, calendar: calendar) {
            try store.setHabit(item.id, done: true, on: today, calendar: calendar)
        }
    }
}
#endif
