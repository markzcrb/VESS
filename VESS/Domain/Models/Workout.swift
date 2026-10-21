import Foundation

/// A planned or completed workout. Deliberately simple: VESS tracks
/// consistency, it is not a specialized strength-training log.
nonisolated struct Workout: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var type: WorkoutType
    var durationMinutes: Int?
    var exercises: [Exercise]
    var scheduledDate: Date?
    var completedAt: Date?
    var notes: String?
    /// The template this workout was created from, if any.
    var templateID: UUID?
    /// How hard an entered workout felt.
    var effort: WorkoutEffort? = nil
    /// Where it came from; `nil` in payloads from earlier builds, which were
    /// all entered.
    var source: WorkoutSource? = nil
    var startedAt: Date? = nil
    /// Recorded workouts: measured by Apple Health. Entered workouts: the
    /// estimate from `WorkoutEnergy`, kept as it was when saved.
    var activeEnergyKilocalories: Double? = nil
    /// Only when the workout itself recorded a distance.
    var distanceMeters: Double? = nil
    /// The recording device, such as "Apple Watch". Never a personal device name.
    var deviceName: String? = nil

    var isCompleted: Bool { completedAt != nil }
    var isRecorded: Bool { source == .recorded }
}

nonisolated enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case strength
    case running
    case walking
    case cycling
    case hiit
    case yoga
    case mobility
    case swimming
    case other
}

/// How hard an entered workout felt; picks its MET value.
nonisolated enum WorkoutEffort: String, Codable, CaseIterable, Sendable {
    case easy
    case moderate
    case hard
}

nonisolated enum WorkoutSource: String, Codable, Sendable {
    /// Read from Apple Health: duration and energy are measurements.
    case recorded
    /// Entered in VESS: energy is an estimate.
    case entered
}

nonisolated struct Exercise: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var sets: Int?
    var reps: Int?
    var weightKilograms: Double?
    var durationSeconds: Int?
    var notes: String?
}
