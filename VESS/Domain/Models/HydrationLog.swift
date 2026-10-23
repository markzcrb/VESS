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
    /// Grams of pure alcohol. `nil` for drinks without alcohol and for logs
    /// saved before alcohol was tracked (they decode without it).
    var alcoholGrams: Double? = nil

    /// The estimated amount counted toward the daily water target.
    var hydrationMilliliters: Double {
        volumeMilliliters * min(max(hydrationContributionPercent, 0), 100) / 100
    }

    var isAlcoholic: Bool { drinkType == .alcohol }

    /// kcal that count in the day's energy total: alcoholic drinks only.
    /// Other drinks' kcal are recorded but, as before, not added to energy.
    var energyCalories: Double { isAlcoholic ? calories : 0 }

    /// Standard drinks (10 g of alcohol each).
    var standardDrinks: Double? {
        alcoholGrams.map(StandardDrink.count(alcoholGrams:))
    }

    /// The same drink at another volume and time (editing a logged drink):
    /// kcal, sugar, caffeine and alcohol scale with the volume; the share
    /// toward water stays as it was logged.
    func edited(volumeMilliliters newVolume: Double, loggedAt newDate: Date) -> HydrationLog {
        let volume = max(newVolume, 0)
        let factor = volumeMilliliters > 0 ? volume / volumeMilliliters : 0
        var copy = self
        copy.volumeMilliliters = volume
        copy.calories = calories * factor
        copy.sugarGrams = sugarGrams * factor
        copy.caffeineMilligrams = caffeineMilligrams * factor
        copy.alcoholGrams = alcoholGrams.map { $0 * factor }
        copy.loggedAt = newDate
        return copy
    }
}

nonisolated extension Sequence where Element == HydrationLog {
    /// Alcoholic drinks as energy items for the Energy screen's chart,
    /// before-noon share and daily totals.
    var alcoholEnergy: [IntakeAnalysis.EnergyItem] {
        compactMap { log in
            log.energyCalories > 0 ? IntakeAnalysis.EnergyItem(date: log.loggedAt, calories: log.energyCalories) : nil
        }
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
