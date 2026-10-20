import Foundation

extension DayWord {
    var title: LocalizedStringResource {
        switch self {
        case .freshStart: "Fresh start"
        case .onTrack: "On track"
        case .lightSoFar: "Light so far"
        case .fullDay: "Full day"
        }
    }
}

extension DaySummary {
    /// Today's one editorial line, such as "A steady day. Protein is the one
    /// to watch." Calm and observational; over target is never a warning.
    var editorialLine: String {
        let lead: String
        switch dayWord {
        case .freshStart:
            return String(localized: "Nothing logged yet today.")
        case .onTrack:
            lead = String(localized: "A steady day.")
        case .lightSoFar:
            lead = String(localized: "A lighter day so far.")
        case .fullDay:
            return consumed.calories - targets.calories > 0
                ? String(localized: "A full day. A little above is still a steady day.")
                : String(localized: "A full day, right at your target.")
        }
        return [lead, watchSentence].compactMap(\.self).joined(separator: " ")
    }

    private var watchSentence: String? {
        switch (isProteinBehind, isWaterBehind) {
        case (true, true): String(localized: "Protein and water are the ones to watch.")
        case (true, false): String(localized: "Protein is the one to watch.")
        case (false, true): String(localized: "Water is the one to watch.")
        case (false, false): nil
        }
    }
}

/// Today's insight card: one factual sentence about the day, built only from
/// what was logged. `nil` when there is nothing worth saying.
enum TodayInsight {
    struct Content {
        let text: String
        /// Set when the card offers to log the next meal.
        var logMeal: MealType?
    }

    static func content(
        summary: DaySummary,
        entries: [FoodLogEntry],
        history: [FoodLogEntry],
        now: Date,
        calendar: Calendar
    ) -> Content? {
        let protein = VESSFormat.grams(summary.consumed.proteinGrams)
        let proteinTarget = VESSFormat.grams(summary.targets.proteinGrams)

        if entries.isEmpty {
            let meal = MealType.likely(at: now, calendar: calendar)
            if let usual = history.usualTime(for: meal, calendar: calendar),
               let time = calendar.date(bySettingHour: usual.hour ?? 0, minute: usual.minute ?? 0, second: 0, of: now) {
                let mealName = String(localized: meal.title).lowercased()
                return Content(
                    text: String(localized: "You usually have \(mealName) around \(time.formatted(date: .omitted, time: .shortened)). Log it and your Fuel score starts building."),
                    logMeal: meal
                )
            }
            return Content(text: String(localized: "Log your first meal and your Fuel score starts building."), logMeal: meal)
        }

        if summary.dayWord == .fullDay {
            let consumed = VESSFormat.calories(summary.consumed.calories)
            let target = VESSFormat.calories(summary.targets.calories)
            let above = summary.consumed.calories - summary.targets.calories
            if above > 0 {
                return Content(text: String(localized: "Energy is at \(consumed) of \(target) kcal, \(VESSFormat.calories(above)) above your guide. One day doesn't define a pattern."))
            }
            return Content(text: String(localized: "Energy is at \(consumed) of \(target) kcal, right at your guide."))
        }

        if summary.isProteinBehind {
            var sentence = String(localized: "Protein is at \(protein) of \(proteinTarget) g")
            let total = summary.consumed.proteinGrams
            let afterNoon = entries
                .filter { calendar.component(.hour, from: $0.loggedAt) >= 12 }
                .reduce(0) { $0 + $1.nutrition.proteinGrams }
            if total > 0, afterNoon / total >= 0.5 {
                let share = (afterNoon / total).formatted(.percent.precision(.fractionLength(0)))
                sentence += String(localized: ", and \(share) of it came after noon")
            }
            sentence += "."
            let dinnerLogged = !entries.entries(for: .dinner).isEmpty
            if !dinnerLogged, calendar.component(.hour, from: now) < MealType.dinner.suggestionEndHour {
                sentence += " " + String(localized: "A protein-led dinner closes the gap.")
            }
            return Content(text: sentence)
        }

        if summary.isWaterBehind {
            let water = VESSFormat.liters(fromMilliliters: summary.hydration.consumedMilliliters)
            let waterTarget = VESSFormat.liters(fromMilliliters: summary.hydration.targetMilliliters)
            return Content(text: String(localized: "Water is at \(water) of \(waterTarget) L so far today."))
        }
        return nil
    }
}

enum Greeting {
    static func text(for date: Date, name: String, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch (hour, trimmed.isEmpty) {
        case (5..<12, false): return String(localized: "Good morning, \(trimmed)")
        case (12..<17, false): return String(localized: "Good afternoon, \(trimmed)")
        case (_, false): return String(localized: "Good evening, \(trimmed)")
        case (5..<12, true): return String(localized: "Good morning")
        case (12..<17, true): return String(localized: "Good afternoon")
        case (_, true): return String(localized: "Good evening")
        }
    }
}
