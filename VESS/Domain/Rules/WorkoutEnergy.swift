import Foundation

/// The energy estimate for a workout the user enters (PRODUCT-LOGIC.md #8,
/// decided 2026-10-21): MET × body weight (kg) × hours, with a fixed MET per
/// type and effort from the Compendium of Physical Activities. Always shown
/// with "≈" and labelled an estimate. Recorded workouts use Apple Health's
/// measurement instead. Steps are never estimated.
nonisolated enum WorkoutEnergy {
    /// Metabolic equivalents per type, for easy / moderate / hard.
    static func met(for type: WorkoutType, effort: WorkoutEffort) -> Double {
        let values: (easy: Double, moderate: Double, hard: Double) = switch type {
        case .walking: (2.8, 3.5, 4.3)
        case .running: (7.0, 9.8, 11.5)
        case .cycling: (4.0, 6.8, 10.0)
        case .strength: (3.5, 5.0, 6.0)
        case .yoga: (2.5, 3.0, 4.0)
        case .swimming: (5.8, 8.0, 9.8)
        case .hiit: (5.0, 8.0, 10.0)
        case .mobility: (2.3, 2.5, 3.0)
        case .other: (3.0, 4.0, 6.0)
        }
        return switch effort {
        case .easy: values.easy
        case .moderate: values.moderate
        case .hard: values.hard
        }
    }

    /// Kilocalories, rounded to whole numbers; `nil` without a usable weight
    /// or duration.
    static func estimate(type: WorkoutType, effort: WorkoutEffort, minutes: Int, weightKilograms: Double) -> Double? {
        guard minutes > 0, weightKilograms > 0 else { return nil }
        return (met(for: type, effort: effort) * weightKilograms * Double(minutes) / 60).rounded()
    }
}
