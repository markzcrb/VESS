import Foundation
import Testing
@testable import VESS

@Suite("UMEVA+ from the server: entitlement mapping and retries")
struct EntitlementTests {
    private func decode(_ json: String) throws -> EntitlementResponse {
        try JSONDecoder().decode(EntitlementResponse.self, from: Data(json.utf8))
    }

    @Test("The server's answer maps: plan, product, expiry (JavaScript or Postgres time), limits, rejections")
    func mapping() throws {
        let plus = try decode(#"{"plan":"plus","product_id":"app.umeva.ios.plus.annual","expires_at":"2026-11-04T10:00:00.000Z","limits":{"coach":15,"photo":10,"chef":5},"rejected":[]}"#)
        #expect(plus.plan == .plus && plus.productID == "app.umeva.ios.plus.annual")
        #expect(plus.limits == .init(coach: 15, photo: 10, chef: 5))
        #expect(plus.limits.value(for: .chef) == 5)
        #expect(plus.expiresAt == EntitlementResponse.date(from: "2026-11-04T10:00:00Z"))
        let postgres = try decode(#"{"plan":"plus","product_id":"p","expires_at":"2026-11-04T10:00:00+00:00","limits":{"coach":15,"photo":10,"chef":5}}"#)
        #expect(postgres.expiresAt == plus.expiresAt && postgres.rejected.isEmpty)
        let free = try decode(#"{"plan":"free","product_id":null,"expires_at":null,"limits":{"coach":3,"photo":1,"chef":1},"rejected":[{"reason":"other_account"}]}"#)
        #expect(free.plan == .free && free.expiresAt == nil && free.rejected == [.init(reason: "other_account")])
        let tester = try decode(#"{"plan":"tester","limits":{"coach":50,"photo":30,"chef":30},"rejected":[]}"#)
        #expect(tester.plan == .tester)
        // The app's own cache round-trips.
        #expect(try JSONDecoder().decode(EntitlementResponse.self, from: JSONEncoder().encode(plus)) == plus)
    }

    @Test("What the app shows: the server decides; a valid StoreKit purchase the server doesn't count is 'activating'")
    func status() throws {
        let limits = EntitlementResponse.Limits(coach: 3, photo: 1, chef: 1)
        let free = EntitlementResponse(plan: .free, limits: limits)
        #expect(EntitlementRules.status(response: free, storeKitHasPlus: false) == .free)
        #expect(EntitlementRules.status(response: free, storeKitHasPlus: true) == .activating)
        #expect(EntitlementRules.status(response: nil, storeKitHasPlus: true) == .activating, "The call failed")
        let otherAccount = EntitlementResponse(plan: .free, limits: limits, rejected: [.init(reason: "other_account")])
        #expect(EntitlementRules.status(response: otherAccount, storeKitHasPlus: true) == .otherAccount)
        let plus = EntitlementResponse(plan: .plus, expiresAt: .distantFuture, limits: .init(coach: 15, photo: 10, chef: 5))
        #expect(EntitlementRules.status(response: plus, storeKitHasPlus: false) == .plus(expiresAt: .distantFuture), "Bought on another device")
        #expect(EntitlementRules.status(response: EntitlementResponse(plan: .tester, limits: limits), storeKitHasPlus: false) == .tester)
    }

    @Test("Retries after 2 s, 10 s and 60 s while activating, then wait for the next launch")
    func backoff() {
        #expect(EntitlementRules.retryDelays == [2, 10, 60])
        #expect(EntitlementRules.retryDelay(afterAttempt: 0) == 2)
        #expect(EntitlementRules.retryDelay(afterAttempt: 1) == 10)
        #expect(EntitlementRules.retryDelay(afterAttempt: 2) == 60)
        #expect(EntitlementRules.retryDelay(afterAttempt: 3) == nil)
        #expect(EntitlementRules.shouldRetry(.activating))
        #expect(!EntitlementRules.shouldRetry(.otherAccount) && !EntitlementRules.shouldRetry(.free) && !EntitlementRules.shouldRetry(.tester))
    }
}

@MainActor
@Suite("Plan store against the mock server")
struct PlanStoreTests {
    private func defaults() -> UserDefaults {
        let name = "test.plan.\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    private func account(_ scenario: AIMockTransport.Scenario, signedIn: Bool = true) -> AccountStore {
        AccountStore(config: SupabaseConfig(url: URL(string: "https://mock.vess.invalid")!, publishableKey: "mock", appleSignInEnabled: false),
                     transport: AIMockTransport(scenario: scenario),
                     store: MemorySessionStore(signedIn ? AIMockTransport.session : nil))
    }

    @Test("UMEVA+ on the server: plan, limits and badge come from the answer, and are cached")
    func plus() async {
        let defaults = defaults()
        let store = PlanStore(account: account(.plus), defaults: defaults, signedTransactions: { ["jws"] })
        await store.sync()
        #expect(store.isPlus)
        #expect(store.knownLimit(.coach) == 15 && store.knownLimit(.chef) == 5)
        let reopened = PlanStore(account: account(.plus), defaults: defaults, signedTransactions: { [] })
        #expect(reopened.knownLimit(.photo) == 10, "Shown offline from the cache")
    }

    @Test("A valid StoreKit purchase the server answers free for: activating, not an error")
    func activating() async {
        let store = PlanStore(account: account(.ok), defaults: defaults(), signedTransactions: { ["jws"] })
        await store.sync()
        #expect(store.status == .activating)
        #expect(!store.isPlus)
    }

    @Test("Signed out: nothing is assumed, nothing is sent")
    func signedOut() async {
        let store = PlanStore(account: account(.plus, signedIn: false), defaults: defaults(), signedTransactions: { [] })
        await store.sync()
        #expect(store.response == nil && store.status == .free)
        #expect(await store.limit(.coach) == nil)
    }
}
