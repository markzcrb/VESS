import Foundation
import Testing
@testable import VESS

@Suite("Health sync: one failing type never takes the others down")
struct HealthSyncTests {
    private struct NotDetermined: Error {}

    /// A reader whose snapshot or authorization can be scripted.
    private final class ScriptedHealthService: HealthService, @unchecked Sendable {
        var result: Result<HealthSnapshot?, any Error>
        var needsNewTypes = false
        private(set) var authorizationRequests = 0

        init(_ result: Result<HealthSnapshot?, any Error>) { self.result = result }

        var isAvailable: Bool { true }
        func requestAuthorization() async throws { authorizationRequests += 1 }
        func needsAuthorization() async -> Bool { needsNewTypes }
        func snapshot(now: Date, calendar: Calendar, stepsTarget: Int) async throws -> HealthSnapshot? { try result.get() }
    }

    @Test("A read that fails gives its empty value and is recorded; the others keep their values")
    func readLog() async {
        let log = HealthReadLog()
        let steps = await log.read(.steps, empty: 0) { 6420 }
        let sleep: [SleepSample] = await log.read(.sleep, empty: []) { throw NSError(domain: "com.apple.healthkit", code: 5) }
        #expect(steps == 6420 && sleep.isEmpty)
        #expect(log.issues.keys.sorted { $0.rawValue < $1.rawValue } == [.sleep])
        #expect(log.issues[.sleep]?.hasPrefix("com.apple.healthkit 5") == true)
    }

    @Test("Sleep failing alone: the state stays available with steps, and sleep is listed as an issue")
    @MainActor
    func partialFailure() async {
        let snapshot = HealthSnapshot(steps: 6420, stepsTarget: 8000, activeEnergyKilocalories: 412, updatedAt: .now,
                                      readIssues: [.sleep: "com.apple.healthkit 5: Authorization not determined"])
        let store = HealthDataStore(service: ScriptedHealthService(.success(snapshot)), didRequestAccess: true)
        await store.refresh(stepsTarget: 8000)
        #expect(store.state.snapshot?.steps == 6420)
        guard case .available(let shown) = store.state else {
            Issue.record("Expected available, got \(store.state)")
            return
        }
        #expect(shown.readIssues[.sleep] != nil && shown.readIssues[.steps] == nil)
        #expect(store.lastError?.contains("sleep") == true)
    }

    @Test("Only when every read failed is the state failed, keeping the last known values")
    @MainActor
    func allFailed() async {
        let service = ScriptedHealthService(.failure(HealthReadFailure(issues: [.steps: "x", .sleep: "y"])))
        let store = HealthDataStore(service: service, didRequestAccess: true)
        await store.refresh(stepsTarget: 8000)
        #expect(store.state == .failed(lastKnown: nil))
        #expect(store.lastError == "sleep: y; steps: x")
    }

    @Test("\"Isn't sharing · Check access\" shows when sync failed, nothing is shared, or that kind failed; not for an empty working read")
    @MainActor
    func accessRow() {
        let fine = HealthSnapshot(steps: 1, stepsTarget: 8000, activeEnergyKilocalories: nil, updatedAt: .now)
        var sleepFailed = fine
        sleepFailed.readIssues = [.sleep: "com.apple.healthkit 5"]
        #expect(!HealthAccessRow.isShown(.available(fine), kinds: [.sleep]), "Working read, just no sleep: the empty line instead")
        #expect(HealthAccessRow.isShown(.available(sleepFailed), kinds: [.sleep]))
        #expect(!HealthAccessRow.isShown(.available(sleepFailed), kinds: [.restingHeartRate]), "Heart isn't affected by sleep failing")
        #expect(HealthAccessRow.isShown(.nothingShared, kinds: [.sleep]) && HealthAccessRow.isShown(.notConnected, kinds: [.sleep]))
        #expect(HealthAccessRow.isShown(.failed(lastKnown: nil), kinds: [.sleep]) && !HealthAccessRow.isShown(.syncing, kinds: [.sleep]))
    }

    @Test("Connected before new types were added: they're asked for once, then read")
    @MainActor
    func asksForNewTypesOnce() async {
        let service = ScriptedHealthService(.success(HealthSnapshot(steps: 1, stepsTarget: 8000, activeEnergyKilocalories: nil, updatedAt: .now)))
        service.needsNewTypes = true
        let store = HealthDataStore(service: service, didRequestAccess: true)
        await store.refresh(stepsTarget: 8000)
        await store.refresh(stepsTarget: 8000)
        #expect(service.authorizationRequests == 1)
        #expect(store.state.snapshot?.steps == 1)
    }
}
