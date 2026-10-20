import Foundation

/// What Apple Health reported most recently. Read-only: VESS never writes
/// to Health yet, and never estimates steps.
nonisolated struct HealthSnapshot: Equatable, Sendable {
    var steps: Int
    /// The user's step goal.
    var stepsTarget: Int
    var activeEnergyKilocalories: Double?
    /// When Health last delivered these values.
    var updatedAt: Date

    /// 0...1 of the step goal.
    var stepsFraction: Double {
        stepsTarget > 0 ? min(Double(steps) / Double(stepsTarget), 1) : 0
    }
}

/// The state of the Apple Health connection, as screens show it.
nonisolated enum HealthSyncState: Equatable, Sendable {
    /// No permission yet: steps show "—" (S4).
    case notConnected
    /// The first read is in progress (S2).
    case syncing
    case available(HealthSnapshot)
    /// The last read failed; the last known values stay visible (D07).
    case failed(lastKnown: HealthSnapshot?)

    /// The values to show, if any.
    var snapshot: HealthSnapshot? {
        switch self {
        case .available(let snapshot): snapshot
        case .failed(let lastKnown): lastKnown
        case .notConnected, .syncing: nil
        }
    }
}
