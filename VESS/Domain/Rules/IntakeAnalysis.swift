import Foundation

/// How a day's intake is spread over time and across macronutrients.
/// Pure and deterministic.
nonisolated enum IntakeAnalysis {
    /// Share of the day's energy logged before 12:00, 0...1. `nil` when
    /// nothing with energy is logged.
    static func beforeNoonShare(_ entries: [FoodLogEntry], calendar: Calendar) -> Double? {
        let total = entries.reduce(0) { $0 + $1.nutrition.calories }
        guard total > 0 else { return nil }
        let morning = entries
            .filter { calendar.component(.hour, from: $0.loggedAt) < 12 }
            .reduce(0) { $0 + $1.nutrition.calories }
        return morning / total
    }

    /// One step of the running total through the day.
    struct CumulativePoint: Equatable, Sendable {
        /// Minutes since midnight.
        let minute: Int
        let calories: Double
    }

    /// Running energy total at each logging time, oldest first. Entries at
    /// the same minute are combined.
    static func cumulative(_ entries: [FoodLogEntry], calendar: Calendar) -> [CumulativePoint] {
        var byMinute: [Int: Double] = [:]
        for entry in entries {
            let parts = calendar.dateComponents([.hour, .minute], from: entry.loggedAt)
            byMinute[(parts.hour ?? 0) * 60 + (parts.minute ?? 0), default: 0] += entry.nutrition.calories
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

    static func dailyTotals(_ entries: [FoodLogEntry], endingOn day: Date, days: Int, calendar: Calendar) -> [DayTotal] {
        let last = calendar.startOfDay(for: day)
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: last) else { return nil }
            let dayEntries = entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
            return DayTotal(day: date, nutrition: dayEntries.totalNutrition, hasEntries: !dayEntries.isEmpty)
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

    /// Energy against the prorated target. Optimal inside the Fuel full-marks
    /// band (90–105 %); sufficient above it (being ahead is never "low") and
    /// from 63 % (0.7 of full marks); low only when well under.
    static func energy(ratio: Double) -> StatusLevel {
        if FuelScore.energyFullMarks.contains(ratio) { return .optimal }
        if ratio > FuelScore.energyFullMarks.upperBound { return .sufficient }
        return level(FuelScore.energyScore(ratio), optimal: 1, sufficient: 0.7)
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
