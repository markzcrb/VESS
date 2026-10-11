import Foundation

/// A supplement the user has chosen to take. VESS records the user's own
/// dosage and never suggests one.
nonisolated struct Supplement: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var dosage: Double
    var unit: SupplementUnit
    var schedule: SupplementSchedule
    /// Time of day for the reminder (hour and minute).
    var reminderTime: DateComponents?
    var reminderEnabled: Bool
    var notes: String?
}

nonisolated enum SupplementUnit: String, Codable, CaseIterable, Sendable {
    case milligram
    case microgram
    case gram
    case internationalUnit
    case capsule
    case tablet
    case milliliter
}

nonisolated enum SupplementSchedule: Codable, Hashable, Sendable {
    case daily
    case weekdays(Set<Locale.Weekday>)
    case asNeeded
}

nonisolated struct SupplementLog: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let userID: UUID
    var supplementID: UUID
    var takenAt: Date
    var dosage: Double
    var unit: SupplementUnit
}
