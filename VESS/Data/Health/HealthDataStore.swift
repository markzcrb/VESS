import Foundation
import Observation
import OSLog

/// Holds the Apple Health state for screens and runs the read-only reader
/// (steps, workouts, active energy, weight). Until the user connects, the
/// state is `.notConnected` and screens show "—"; steps are never estimated.
@Observable
final class HealthDataStore {
    var state: HealthSyncState
    /// The last authorization or read error, as text (shown on the Debug
    /// Apple Health screen). Kinds that failed alone are in the snapshot's
    /// `readIssues`.
    private(set) var lastError: String?
    /// When a read last succeeded; `nil` before the first one this launch.
    private(set) var lastSuccessAt: Date?

    private let service: (any HealthService)?
    /// Whether the user has been through the permission sheet. Health never
    /// tells apps whether read access was granted, only whether it asked.
    private var didRequestAccess: Bool
    /// Off for demo stores, so a demo never marks the real app as connected.
    private let remembersAccess: Bool
    private let logger = Logger(subsystem: "VESS", category: "Health")
    /// Asked for newly added types this launch already.
    private var didAskForNewTypes = false

    /// DEBUG `-healthNoReask`: read as an older build would, without asking
    /// for new types first, to see the errors that causes.
    private static var skipsReask: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-healthNoReask")
        #else
        false
        #endif
    }

    private static let accessKey = "health.didRequestAccess"

    init(state: HealthSyncState = .notConnected, service: (any HealthService)? = nil, didRequestAccess: Bool? = nil, lastSuccessAt: Date? = nil) {
        self.state = state
        self.lastSuccessAt = lastSuccessAt
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
            lastError = HealthReadLog.describe(error)
            logger.error("Health authorization failed: \(self.lastError ?? "", privacy: .public)")
            state = .failed(lastKnown: state.snapshot)
            return
        }
        didRequestAccess = true
        if remembersAccess { UserDefaults.standard.set(true, forKey: Self.accessKey) }
        await refresh(stepsTarget: stepsTarget)
    }

    /// Stale values on screen (`HealthFreshness`).
    var isStale: Bool { HealthFreshness.isStale(state, lastSuccess: lastSuccessAt, now: AppClock.now) }

    /// When Health was last updated, for "updated 3 h ago".
    var updatedAt: Date? { lastSuccessAt ?? state.snapshot?.updatedAt }

    /// Reads again if the user has connected. The last values stay on
    /// screen while it reads, and after a failure (D07).
    func refresh(stepsTarget: Int) async {
        guard let service, didRequestAccess else { return }
        let lastKnown = state.snapshot
        if lastKnown == nil { state = .syncing }
        // Connected with a build that read fewer types: ask once for the new
        // ones (the sheet lists only those), so they don't stay undetermined.
        if !didAskForNewTypes, !Self.skipsReask, await service.needsAuthorization() {
            didAskForNewTypes = true
            do {
                try await service.requestAuthorization()
            } catch {
                lastError = HealthReadLog.describe(error)
                logger.error("Health authorization for new types failed: \(self.lastError ?? "", privacy: .public)")
            }
        }
        do {
            if let snapshot = try await service.snapshot(now: AppClock.now, calendar: .current, stepsTarget: stepsTarget) {
                // Kinds that failed alone are listed in the snapshot; the rest show.
                state = .available(snapshot)
                lastSuccessAt = AppClock.now
                lastError = snapshot.readIssues.isEmpty ? nil : HealthReadFailure(issues: snapshot.readIssues).description
            } else {
                state = .nothingShared
                lastSuccessAt = AppClock.now
                lastError = nil
            }
        } catch {
            lastError = (error as? HealthReadFailure)?.description ?? HealthReadLog.describe(error)
            logger.error("Health read failed: \(self.lastError ?? "", privacy: .public)")
            state = .failed(lastKnown: lastKnown)
        }
    }
}
