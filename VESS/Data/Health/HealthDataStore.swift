import Observation

/// Holds the Apple Health state for screens. The read-only HealthKit reader
/// (steps, workouts, active energy, weight) plugs in here with the Activity
/// screens; until then the app reports `.notConnected` and shows "—".
@Observable
final class HealthDataStore {
    var state: HealthSyncState

    init(state: HealthSyncState = .notConnected) {
        self.state = state
    }
}
