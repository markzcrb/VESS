import Foundation

/// How a day's intake is spread over time and across macronutrients.
/// Pure and deterministic.
nonisolated enum IntakeAnalysis {
    /// Energy that isn't a food entry but counts in the day's total:
    /// alcoholic drinks (`HydrationLog.alcoholEnergy`).
    struct EnergyItem: Equatable, Sendable {
        let date: Date
        let calories: Double
    }

    /// Share of the day's energy logged before 12:00, 0...1. `nil` when
    /// nothing with energy is logged.
    static func beforeNoonShare(_ entries: [FoodLogEntry], extra: [EnergyItem] = [], calendar: Calendar) -> Double? {
        let items = Self.items(entries, extra: extra)
        let total = items.reduce(0) { $0 + $1.calories }
        guard total > 0 else { return nil }
        let morning = items
            .filter { calendar.component(.hour, from: $0.date) < 12 }
            .reduce(0) { $0 + $1.calories }
        return morning / total
    }

    private static func items(_ entries: [FoodLogEntry], extra: [EnergyItem]) -> [EnergyItem] {
        entries.map { EnergyItem(date: $0.loggedAt, calories: $0.nutrition.calories) } + extra
    }

    /// One step of the running total through the day.
    struct CumulativePoint: Equatable, Sendable {
        /// Minutes since midnight.
        let minute: Int
        let calories: Double
    }

    /// Running energy total at each logging time, oldest first. Entries at
    /// the same minute are combined.
    static func cumulative(_ entries: [FoodLogEntry], extra: [EnergyItem] = [], calendar: Calendar) -> [CumulativePoint] {
        var byMinute: [Int: Double] = [:]
        for item in items(entries, extra: extra) {
            let parts = calendar.dateComponents([.hour, .minute], from: item.date)
            byMinute[(parts.hour ?? 0) * 60 + (parts.minute ?? 0), default: 0] += item.calories
        }
        var running = 0.0
        return byMinute.keys.sorted().map { minute in
            running += byMinute[minute] ?? 0
            return CumulativePoint(minute: minute, calories: running)
        }
    }

    /// Totals for `days` consecutive days ending on `day`, oldest first.
    /// Days without entries have zero totals and `hasEntries == false`.
    struct DayTotal: Equatable, Sendable {
        let day: Date
        let nutrition: NutritionFacts
        let hasEntries: Bool
    }

    /// `extra` energy (alcohol) adds to each day's calories, and a day with
    /// only extra energy still counts as logged.
    static func dailyTotals(_ entries: [FoodLogEntry], extra: [EnergyItem] = [], endingOn day: Date, days: Int, calendar: Calendar) -> [DayTotal] {
        let last = calendar.startOfDay(for: day)
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: last) else { return nil }
            let dayEntries = entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
            let dayExtra = extra.filter { calendar.isDate($0.date, inSameDayAs: date) }
            var nutrition = dayEntries.totalNutrition
            nutrition.calories += dayExtra.reduce(0) { $0 + $1.calories }
            return DayTotal(day: date, nutrition: nutrition, hasEntries: !dayEntries.isEmpty || !dayExtra.isEmpty)
        }
    }

    /// Average of the days that have entries, or `nil` when none do.
    static func average(_ totals: [DayTotal], _ value: (NutritionFacts) -> Double) -> Double? {
        let logged = totals.filter(\.hasEntries)
        guard !logged.isEmpty else { return nil }
        return logged.reduce(0) { $0 + value($1.nutrition) } / Double(logged.count)
    }

    /// Share of energy from protein, carbs and fat (4, 4 and 9 kcal per gram),
    /// summing to 1. `nil` when all three are zero.
    struct EnergySplit: Equatable, Sendable {
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    static func energySplit(proteinGrams: Double, carbGrams: Double, fatGrams: Double) -> EnergySplit? {
        let protein = proteinGrams * 4, carbs = carbGrams * 4, fat = fatGrams * 9
        let total = protein + carbs + fat
        guard total > 0 else { return nil }
        return EnergySplit(protein: protein / total, carbs: carbs / total, fat: fat / total)
    }
}

/// How a measure on the Energy screen compares with its range.
nonisolated enum StatusLevel: Equatable, Sendable {
    case low, sufficient, optimal

    /// The approved Energy (02) bands (PRODUCT-LOGIC.md), independent of Fuel.
    static let energyOptimal = 0.90...1.05
    static let energySufficientFrom = 0.63

    /// Energy against the prorated target. Optimal at 90–105 %; sufficient
    /// above it (being ahead is never "low") and from 63 %; low only when
    /// well under.
    static func energy(ratio: Double) -> StatusLevel {
        if energyOptimal.contains(ratio) { return .optimal }
        if ratio > energyOptimal.upperBound { return .sufficient }
        return ratio >= energySufficientFrom ? .sufficient : .low
    }

    /// Meal regularity (`MealRegularity.score`): optimal from 0.85, sufficient from 0.6.
    static func regularity(_ score: Double) -> StatusLevel {
        level(score, optimal: 0.85, sufficient: 0.6)
    }

    private static func level(_ value: Double, optimal: Double, sufficient: Double) -> StatusLevel {
        if value >= optimal { return .optimal }
        if value >= sufficient { return .sufficient }
        return .low
    }
}
