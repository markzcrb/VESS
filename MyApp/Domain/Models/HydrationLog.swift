import Foundation

/// One drink consumed. Values are snapshots, like `FoodLogEntry`.
///
/// `volumeMilliliters` is what was drunk. `hydrationMilliliters` is the
/// estimated part of it that counts toward the water target. The two are
/// always kept and shown separately.
nonisolated struct HydrationLog: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var drinkID: UUID?
    var drinkName: String
    var drinkType: DrinkType
    var volumeMilliliters: Double
    /// 0–100, captured when logged.
    var hydrationContributionPercent: Double
    var calories: Double
    var sugarGrams: Double
    var caffeineMilligrams: Double
    var loggedAt: Date

    /// The estimated amount counted toward the daily water target.
    var hydrationMilliliters: Double {
        volumeMilliliters * min(max(hydrationContributionPercent, 0), 100) / 100
    }
}

/// Progress toward the daily water target, based on hydration contributions.
nonisolated struct HydrationProgress: Hashable, Sendable {
    /// Sum of hydration contributions.
    let consumedMilliliters: Double
    /// Sum of volumes actually drunk, for display beside the contribution.
    let volumeMilliliters: Double
    let targetMilliliters: Double

    /// Builds progress from the logs on `day`'s calendar day.
    init(logs: [HydrationLog], targetMilliliters: Double, day: Date, calendar: Calendar) {
        let dayLogs = logs.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
        self.consumedMilliliters = dayLogs.reduce(0) { $0 + $1.hydrationMilliliters }
        self.volumeMilliliters = dayLogs.reduce(0) { $0 + $1.volumeMilliliters }
        self.targetMilliliters = targetMilliliters
    }

    /// 0...1, for progress indicators.
    var fractionComplete: Double {
        guard targetMilliliters > 0 else { return 0 }
        return min(consumedMilliliters / targetMilliliters, 1)
    }

    var remainingMilliliters: Double {
        max(targetMilliliters - consumedMilliliters, 0)
    }

    var isTargetReached: Bool {
        targetMilliliters > 0 && consumedMilliliters >= targetMilliliters
    }
}
