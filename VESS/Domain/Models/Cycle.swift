import Foundation

/// One logged day of cycle tracking (13, 15): flow, symptoms and a note.
/// Opt-in, stored only on this iPhone and never shared with Apple Health.
/// Sent nowhere, except a summary (cycle day, next estimated window) with a
/// Coach question when "Share cycle with Coach" is on. One record per day.
nonisolated struct CycleDay: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// The start of the logged day.
    var day: Date
    var flow: CycleFlow
    var symptoms: Set<CycleSymptom>
    var note: String?

    /// Nothing worth keeping: saving it removes the day instead.
    var isEmpty: Bool {
        flow == .none && symptoms.isEmpty && (note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

nonisolated enum CycleFlow: String, Codable, CaseIterable, Sendable {
    case none, spotting, light, medium, heavy

    /// Light, medium and heavy flow make a period day. Spotting is logged
    /// but never starts or extends a period.
    var isPeriod: Bool {
        switch self {
        case .light, .medium, .heavy: true
        case .none, .spotting: false
        }
    }
}

nonisolated enum CycleSymptom: String, Codable, CaseIterable, Sendable {
    case cramps, headache, bloating, fatigue, lowMood, backPain, cravings
}
