import Foundation

/// One weight measurement, for weight history.
nonisolated struct WeightEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var weightKilograms: Double
    var measuredAt: Date
    var source: MeasurementSource
}

nonisolated enum MeasurementSource: String, Codable, Sendable {
    case manual
    case appleHealth
}

/// Body mass index: weight (kg) divided by height (m) squared.
///
/// Shown only as an informational metric. VESS does not diagnose or
/// classify users based on BMI.
nonisolated struct BodyMassIndex: Hashable, Sendable {
    let value: Double

    /// Returns `nil` for non-positive inputs instead of a meaningless number.
    init?(weightKilograms: Double, heightCentimeters: Double) {
        guard weightKilograms > 0, heightCentimeters > 0 else { return nil }
        let heightMeters = heightCentimeters / 100
        self.value = weightKilograms / (heightMeters * heightMeters)
    }
}
