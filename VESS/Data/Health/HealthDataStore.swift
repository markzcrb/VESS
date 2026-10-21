import Foundation
import Observation
import OSLog

/// Holds the Apple Health state for screens and runs the read-only reader
/// (steps, workouts, active energy, weight). Until the user connects, the
/// state is `.notConnected` and screens show "—"; steps are never estimated.
@Observable
final class HealthDataStore {
    var state: HealthSyncState

    private let service: (any HealthService)?
    /// Whether the user has been through the permission sheet. Health never
    /// tells apps whether read access was granted, only whether it asked.
    private var didRequestAccess: Bool
    /// Off for demo stores, so a demo never marks the real app as connected.
    private let remembersAccess: Bool
    private let logger = Logger(subsystem: "VESS", category: "Health")

    private static let accessKey = "health.didRequestAccess"

    init(state: HealthSyncState = .notConnected, service: (any HealthService)? = nil, didRequestAccess: Bool? = nil) {
        self.state = state
        self.service = service
        self.remembersAccess = didRequestAccess == nil
        self.didRequestAccess = didRequestAccess ?? UserDefaults.standard.bool(forKey: Self.accessKey)
    }

    /// Apple Health exists on this device and there is a reader.
    var canConnect: Bool { service?.isAvailable == true }

    /// "Connect Apple Health": the system sheet, then a first read.
    func connect(stepsTarget: Int) async {
        guard let service else { return }
        do {
            try await service.requestAuthorization()
        } catch {
            logger.error("Health authorization failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(lastKnown: state.snapshot)
            return
        }
        didRequestAccess = true
        if remembersAccess { UserDefaults.standard.set(true, forKey: Self.accessKey) }
        await refresh(stepsTarget: stepsTarget)
    }

    /// Reads again if the user has connected. The last values stay on
    /// screen while it reads, and after a failure (D07).
    func refresh(stepsTarget: Int) async {
        guard let service, didRequestAccess else { return }
        let lastKnown = state.snapshot
        if lastKnown == nil { state = .syncing }
        do {
            if let snapshot = try await service.snapshot(now: AppClock.now, calendar: .current, stepsTarget: stepsTarget) {
                state = .available(snapshot)
            } else {
                state = .nothingShared
            }
        } catch {
            logger.error("Health read failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(lastKnown: lastKnown)
        }
    }
}
