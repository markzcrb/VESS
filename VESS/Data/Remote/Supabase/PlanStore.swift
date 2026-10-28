import Foundation
import Observation
import OSLog

/// UMEVA+ as the server sees it, the one source for what the app shows:
/// the plan, the expiry and the daily AI limits. After a verified purchase,
/// at launch (signed in), on `Transaction.updates` and after Restore, the
/// signed StoreKit transactions go to the `entitlement` function, which
/// verifies them with Apple and answers. The last answer is kept for
/// offline display.
@Observable
final class PlanStore {
    private(set) var response: EntitlementResponse?
    /// StoreKit on this iPhone has a current UMEVA+ purchase.
    private(set) var storeKitHasPlus = false
    private(set) var isSyncing = false

    var status: EntitlementRules.Status {
        EntitlementRules.status(response: response, storeKitHasPlus: storeKitHasPlus)
    }

    /// UMEVA+ (or a tester account) on the server.
    var isPlus: Bool {
        switch status {
        case .plus, .tester: true
        case .free, .activating, .otherAccount: false
        }
    }

    @ObservationIgnored private let account: AccountStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let signedTransactions: () async -> [String]
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    private let logger = Logger(subsystem: AppLog.subsystem, category: "Plan")
    static let cacheKey = "plus.entitlement"

    init(account: AccountStore, defaults: UserDefaults = .standard,
         signedTransactions: @escaping () async -> [String] = { await PlusStore.signedEntitlements() }) {
        self.account = account
        self.defaults = defaults
        self.signedTransactions = signedTransactions
        if account.isSignedIn, let data = defaults.data(forKey: Self.cacheKey) {
            response = try? JSONDecoder().decode(EntitlementResponse.self, from: data)
        }
    }

    /// The server's daily limit for a feature; waits for the first answer.
    /// `nil` offline before any answer (screens then show no count).
    func limit(_ feature: AIFeature) async -> Int? {
        if response == nil { await sync() }
        return response?.limits.value(for: feature)
    }

    /// The last known limit, without waiting.
    func knownLimit(_ feature: AIFeature) -> Int? {
        response?.limits.value(for: feature)
    }

    /// One sync at a time; a second call waits for the one in flight.
    func sync() async {
        if let syncTask { return await syncTask.value }
        let task = Task { await performSync(attempt: 0) }
        syncTask = task
        await task.value
        syncTask = nil
    }

    /// Signed out or account deleted: nothing is assumed any more.
    func reset() {
        retryTask?.cancel()
        response = nil
        defaults.removeObject(forKey: Self.cacheKey)
    }

    private func performSync(attempt: Int) async {
        let signed = await signedTransactions()
        storeKitHasPlus = !signed.isEmpty
        guard account.isSignedIn else {
            reset()
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let answer: EntitlementResponse = try await account.callFunction("entitlement", body: Request(signedTransactions: signed))
            // New limits (UMEVA+ started or ended): counts kept from the old
            // plan ("0 left today") are no longer true; screens ask again.
            if response?.limits != answer.limits { Self.forgetCachedCounts() }
            response = answer
            if let data = try? JSONEncoder().encode(answer) { defaults.set(data, forKey: Self.cacheKey) }
            logger.notice("entitlement: plan \(answer.plan.rawValue, privacy: .public), limits \(answer.limits.coach, privacy: .public)/\(answer.limits.photo, privacy: .public)/\(answer.limits.chef, privacy: .public), \(signed.count, privacy: .public) transaction(s) sent")
            // Reason codes only; never the transactions.
            for rejection in answer.rejected {
                logger.notice("entitlement rejected: \(rejection.reason, privacy: .public)")
            }
        } catch {
            logger.notice("entitlement sync failed: \(String(describing: BackendError.from(error)), privacy: .public)")
        }
        scheduleRetry(after: attempt)
    }

    private func scheduleRetry(after attempt: Int) {
        retryTask?.cancel()
        guard EntitlementRules.shouldRetry(status), let delay = EntitlementRules.retryDelay(afterAttempt: attempt) else { return }
        retryTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await performSync(attempt: attempt + 1)
        }
    }

    /// The "N left today" counts Coach, Photo and AI Chef keep for the day.
    static let cachedCountKeys = ["coach.remaining", "photo.remaining", "chef.remaining"]

    static func forgetCachedCounts() {
        cachedCountKeys.forEach { UserDefaults.standard.set(-1, forKey: $0) }
    }

    nonisolated struct Request: Encodable, Sendable {
        let signedTransactions: [String]
        enum CodingKeys: String, CodingKey { case signedTransactions = "signed_transactions" }
    }
}
