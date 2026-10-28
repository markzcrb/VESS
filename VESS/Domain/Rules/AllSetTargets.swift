import Foundation

/// B03: the daily targets onboarding set, in order. A target that isn't
/// set (zero or less) is left out rather than shown as 0. Pure.
nonisolated enum AllSetTargets {
    enum Kind: Equatable, Sendable {
        case energy(kcal: Double)
        case protein(grams: Double)
        case water(milliliters: Double)
        case steps(Int)
        case sleep(minutes: Int)
    }

    static func rows(for profile: UserProfile) -> [Kind] {
        var rows: [Kind] = []
        if profile.nutritionTargets.calories > 0 { rows.append(.energy(kcal: profile.nutritionTargets.calories)) }
        if profile.nutritionTargets.proteinGrams > 0 { rows.append(.protein(grams: profile.nutritionTargets.proteinGrams)) }
        if profile.waterTargetMilliliters > 0 { rows.append(.water(milliliters: profile.waterTargetMilliliters)) }
        if profile.dailyStepsTarget > 0 { rows.append(.steps(profile.dailyStepsTarget)) }
        if profile.dailySleepTargetMinutes > 0 { rows.append(.sleep(minutes: profile.dailySleepTargetMinutes)) }
        return rows
    }

    /// "Mark" from "Mark Gerasimov"; `nil` with no name.
    static func firstName(_ name: String) -> String? {
        name.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}
