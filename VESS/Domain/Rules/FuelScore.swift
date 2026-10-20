import Foundation

/// The Fuel score: a 0–100 summary of today's logging against the user's
/// full-day targets, the same measure as the metric strip. It is a logging
/// summary, not a health measurement.
///
/// Weights (approved, `Redesign/docs/PRODUCT-LOGIC.md` #1):
/// - 40 % energy: rises with intake to full marks at 100–105 % of target,
///   then declines gently;
/// - 30 % protein, up to the target;
/// - 20 % hydration, up to the target;
/// - 10 % meal regularity: each meal slot with a usual time adds its share
///   when logged near that time (`MealRegularity.dayProgress`).
///
/// The score only rises as the user logs; eating well past the energy target
/// is the only way it falls. When there is no history for regularity, its
/// 10 % is left out and the other weights are rescaled, rather than guessing.
/// Pure and deterministic.
nonisolated struct FuelScore: Equatable, Sendable {
    /// Each part scored 0...1.
    struct Components: Equatable, Sendable {
        let energy: Double
        let protein: Double
        let hydration: Double
        /// `nil` without enough history.
        let regularity: Double?
    }

    static let energyWeight = 0.40
    static let proteinWeight = 0.30
    static let hydrationWeight = 0.20
    static let regularityWeight = 0.10

    /// Energy within this share of the target scores full marks.
    static let energyFullMarks = 1.00...1.05
    /// Above full marks, energy loses all its marks only at this share of
    /// the target: a gentle decline, one fortieth of the score per 10 % over.
    static let energyZeroAbove = 2.05

    /// 0...100.
    let value: Int
    let components: Components

    /// The score for a day, or `nil` before any food is logged ("—").
    ///
    /// - Parameter regularity: `MealRegularity.dayProgress`, 0...1, or `nil`.
    init?(summary: DaySummary, hasLoggedFood: Bool, regularity: Double?) {
        guard hasLoggedFood else { return nil }

        let energy = Self.energyScore(Self.ratio(summary.consumed.calories, of: summary.targets.calories))
        let protein = min(Self.ratio(summary.consumed.proteinGrams, of: summary.targets.proteinGrams), 1)
        let hydration = min(Self.ratio(summary.hydration.consumedMilliliters, of: summary.hydration.targetMilliliters), 1)
        let regularity = regularity.map { min(max($0, 0), 1) }

        var weighted = Self.energyWeight * energy + Self.proteinWeight * protein + Self.hydrationWeight * hydration
        var totalWeight = Self.energyWeight + Self.proteinWeight + Self.hydrationWeight
        if let regularity {
            weighted += Self.regularityWeight * regularity
            totalWeight += Self.regularityWeight
        }

        self.value = Int((weighted / totalWeight * 100).rounded())
        self.components = Components(energy: energy, protein: protein, hydration: hydration, regularity: regularity)
    }

    /// Rises linearly to full marks at the target, holds to 105 %, then
    /// declines linearly to zero at `energyZeroAbove`.
    static func energyScore(_ ratio: Double) -> Double {
        if ratio < energyFullMarks.lowerBound {
            return max(ratio, 0) / energyFullMarks.lowerBound
        }
        if ratio <= energyFullMarks.upperBound {
            return 1
        }
        let span = energyZeroAbove - energyFullMarks.upperBound
        return max(0, 1 - (ratio - energyFullMarks.upperBound) / span)
    }

    private static func ratio(_ value: Double, of target: Double) -> Double {
        target > 0 ? value / target : 0
    }
}

/// How close today's meal times are to the user's usual times.
nonisolated enum MealRegularity {
    /// Minutes away from the usual time at which a meal scores zero.
    static let zeroAfterMinutes = 120.0
    /// Days of history the usual time is taken from.
    static let historyDays = 14

    /// 0...1: for each meal logged today that has a usual time (median of
    /// the last 14 days, at least 3 days), 1 minus the deviation over two
    /// hours; averaged. `nil` when no logged meal has a usual time yet.
    static func score(today: [FoodLogEntry], history: [FoodLogEntry], calendar: Calendar) -> Double? {
        let slots = slotScores(today: today, history: history, calendar: calendar)
        let logged = slots.compactMap(\.self)
        guard !logged.isEmpty else { return nil }
        return logged.reduce(0, +) / Double(logged.count)
    }

    /// 0...1 for Fuel: the same per-meal scores, summed over every slot that
    /// has a usual time, so each meal adds to it and an unlogged one adds
    /// nothing. It never falls as more meals are logged. `nil` when no slot
    /// has a usual time yet.
    static func dayProgress(today: [FoodLogEntry], history: [FoodLogEntry], calendar: Calendar) -> Double? {
        let slots = slotScores(today: today, history: history, calendar: calendar)
        guard !slots.isEmpty else { return nil }
        return slots.reduce(0) { $0 + ($1 ?? 0) } / Double(slots.count)
    }

    /// One value per meal slot with a usual time: its score if logged
    /// today, `nil` if not yet.
    private static func slotScores(today: [FoodLogEntry], history: [FoodLogEntry], calendar: Calendar) -> [Double?] {
        MealType.dayOrder.compactMap { meal -> Double?? in
            guard let usual = history.usualTime(for: meal, calendar: calendar) else { return nil }
            guard let first = today.filter({ $0.mealType == meal }).map(\.loggedAt).min() else { return .some(nil) }
            let parts = calendar.dateComponents([.hour, .minute], from: first)
            let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            let usualMinutes = Double((usual.hour ?? 0) * 60 + (usual.minute ?? 0))
            return .some(max(0, 1 - abs(minutes - usualMinutes) / zeroAfterMinutes))
        }
    }
}
