import Foundation

/// The Fuel score: a 0–100 summary of how today's logging compares with the
/// user's own targets, prorated for the time of day. It is a logging summary,
/// not a health measurement.
///
/// Weights (approved, `Redesign/docs/PRODUCT-LOGIC.md` #1):
/// - 40 % energy versus the prorated target, full marks between 90 and 105 %;
/// - 30 % protein versus the prorated target;
/// - 20 % hydration versus the prorated target;
/// - 10 % meal regularity (`MealRegularity`).
///
/// When there is no history for regularity, its 10 % is left out and the
/// other weights are rescaled, rather than guessing. Pure and deterministic.
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

    /// Energy within this share of the prorated target scores full marks.
    static let energyFullMarks = 0.90...1.05
    /// Above target, energy reaches zero at this share of the prorated target.
    static let energyZeroAbove = 1.50
    /// The day is never judged against less than a quarter of the targets,
    /// so an early breakfast isn't compared with almost nothing.
    static let minimumPace = 0.25

    /// 0...100.
    let value: Int
    let components: Components

    /// The score for a day, or `nil` before any food is logged ("—").
    ///
    /// - Parameter regularity: `MealRegularity.score`, 0...1, or `nil`.
    init?(summary: DaySummary, hasLoggedFood: Bool, regularity: Double?) {
        guard hasLoggedFood else { return nil }
        let pace = max(summary.expectedPace, Self.minimumPace)

        let energyRatio = Self.ratio(summary.consumed.calories, of: summary.targets.calories * pace)
        let energy = Self.energyScore(energyRatio)
        let protein = min(Self.ratio(summary.consumed.proteinGrams, of: summary.targets.proteinGrams * pace), 1)
        let hydration = min(
            Self.ratio(summary.hydration.consumedMilliliters, of: summary.hydration.targetMilliliters * pace),
            1
        )
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

    /// Full marks inside `energyFullMarks`; linear below it; falls to zero
    /// at `energyZeroAbove` above it.
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
        var scores: [Double] = []
        for meal in MealType.dayOrder {
            guard let first = today.filter({ $0.mealType == meal }).map(\.loggedAt).min(),
                  let usual = history.usualTime(for: meal, calendar: calendar) else { continue }
            let parts = calendar.dateComponents([.hour, .minute], from: first)
            let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            let usualMinutes = Double((usual.hour ?? 0) * 60 + (usual.minute ?? 0))
            scores.append(max(0, 1 - abs(minutes - usualMinutes) / zeroAfterMinutes))
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
