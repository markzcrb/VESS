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

    var isCompleted: Bool { completedAt != nil }
}

nonisolated enum WorkoutType: String, Codable, CaseIterable, Sendable {
    case strength
    case running
    case walking
    case cycling
    case hiit
    case yoga
    case mobility
    case other
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
