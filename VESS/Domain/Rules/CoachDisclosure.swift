import Foundation

/// What Coach sends, in the words the consent sheet uses, each with the
/// `CoachContext` JSON keys it covers. The consent text is built from this
/// list, and a test checks the keys against an encoded context, so what we
/// say and what is sent can't drift apart. Keep `APP-STORE-PRIVACY.md`, the
/// Apple Health usage description and the policy draft in step with it.
nonisolated enum CoachDisclosure {
    struct Item: Sendable {
        let label: LocalizedStringResource
        let keys: [String]
    }

    static let items: [Item] = [
        Item(label: "your first name", keys: ["name"]),
        Item(label: "the date and time", keys: ["date", "time"]),
        Item(label: "your daily targets", keys: ["targets"]),
        Item(label: "today's totals, meals and planned meals", keys: ["today", "meals_today", "planned_meals_today"]),
        Item(label: "energy, protein, water, carbs, fat, fiber and sugar for the last 7 and 30 days",
             keys: ["last_7_days", "energy_by_day", "energy_7d_total", "energy_7d_avg_known_days",
                    "protein_by_day", "protein_7d_total", "protein_7d_avg_known_days",
                    "water_by_day", "water_7d_total", "water_7d_avg_known_days",
                    "carbs", "fat", "fiber", "sugar", "last_30_days"]),
        Item(label: "drinks and caffeine", keys: ["drinks_today", "caffeine"]),
        Item(label: "steps, active energy and workouts", keys: ["steps_by_day", "steps_7d_total", "steps_7d_avg_known_days",
                                                               "active_energy", "workouts", "workouts_last_7_days"]),
        Item(label: "sleep, resting heart rate, heart rate variability and the stress estimate", keys: ["sleep", "resting_hr", "hrv", "stress"]),
        Item(label: "weight, goal weight and BMI", keys: ["body"]),
        Item(label: "habits and supplements", keys: ["habits_today", "habits_completion_7d_pct", "supplements_today"]),
        Item(label: "pantry items to use soon", keys: ["pantry_use_soon"]),
        Item(label: "your diet, preferences, allergies and the ingredients you avoid", keys: ["diet", "prefer", "allergens", "avoid"]),
        Item(label: "whether you're pregnant, only if you turned it on", keys: ["pregnant"]),
        Item(label: "your cycle day and next-period estimate, only if you turn on sharing", keys: ["cycle"]),
    ]

    static var allKeys: Set<String> { Set(items.flatMap(\.keys)) }

    /// "your first name, the date and time, … and your cycle day …".
    static func summary(locale: Locale = .current) -> String {
        items.map { String(localized: $0.label) }.formatted(.list(type: .and).locale(locale))
    }
}
