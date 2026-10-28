import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import VESS

@Suite("UMEVA+ entitlement rule")
struct PlusEntitlementRuleTests {
    private let ids: Set<String> = ["plus.monthly", "plus.annual"]
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Active only when it's ours, not revoked, not expired and not upgraded")
    func rule() {
        let later = now.addingTimeInterval(3600), earlier = now.addingTimeInterval(-1)
        #expect(PlusEntitlementRules.isActive(productID: "plus.annual", productIDs: ids, revocationDate: nil, expirationDate: later, isUpgraded: false, now: now))
        #expect(!PlusEntitlementRules.isActive(productID: "other", productIDs: ids, revocationDate: nil, expirationDate: later, isUpgraded: false, now: now))
        #expect(!PlusEntitlementRules.isActive(productID: "plus.annual", productIDs: ids, revocationDate: earlier, expirationDate: later, isUpgraded: false, now: now), "Refunded")
        #expect(!PlusEntitlementRules.isActive(productID: "plus.annual", productIDs: ids, revocationDate: nil, expirationDate: earlier, isUpgraded: false, now: now), "Expired")
        #expect(!PlusEntitlementRules.isActive(productID: "plus.monthly", productIDs: ids, revocationDate: nil, expirationDate: later, isUpgraded: true, now: now), "Upgraded")
        #expect(!PlusEntitlementRules.isActive(productID: "plus.annual", productIDs: ids, revocationDate: nil, expirationDate: nil, isUpgraded: false, now: now))
    }
}

/// Against UMEVAPlusTests.storekit, a copy of VESS.storekit (the 7-day free
/// week on Annual, Monthly without).
@MainActor
@Suite("UMEVA+ with StoreKit Test", .serialized)
struct PlusStoreKitTests {
    private func session() throws -> SKTestSession {
        // A copy of VESS.storekit in the test bundle (the simulator can't read
        // the project folder). Keep the two the same.
        let session = try SKTestSession(configurationFileNamed: "UMEVAPlusTests")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        return session
    }

    /// On a device, the first run after an install can find no products for
    /// a moment while the test session starts; try for up to 3 s.
    private func product(_ plan: VESSPlusView.Plan) async throws -> Product {
        for _ in 0..<10 {
            if let product = try await Product.products(for: [plan.productID]).first { return product }
            try await Task.sleep(for: .milliseconds(300))
        }
        return try #require(try await Product.products(for: [plan.productID]).first)
    }

    @Test("Annual starts with the free week and unlocks UMEVA+")
    func trial() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        guard case .purchased(let transaction) = try await PlusStore.purchase(try await product(.annual)) else {
            Issue.record("Not purchased"); return
        }
        #expect(transaction.offer?.type == .introductory)
        #expect(await PlusStore.isEntitled())
    }

    @Test("A renewal keeps the same original transaction and stays active")
    func renewal() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        guard case .purchased(let first) = try await PlusStore.purchase(try await product(.monthly)) else {
            Issue.record("Not purchased"); return
        }
        try session.forceRenewalOfSubscription(productIdentifier: VESSPlusView.Plan.monthly.productID)
        let renewed = try await latestTransaction(.monthly, after: first.id)
        #expect(renewed.originalID == first.originalID)
        #expect(await PlusStore.isEntitled())
    }

    @Test("A refund revokes it")
    func refund() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        guard case .purchased(let transaction) = try await PlusStore.purchase(try await product(.monthly)) else {
            Issue.record("Not purchased"); return
        }
        try session.refundTransaction(identifier: UInt(transaction.id))
        #expect(await waitUntil { await !PlusStore.isEntitled() })
    }

    @Test("An expired subscription doesn't unlock it")
    func expiry() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        _ = try await PlusStore.purchase(try await product(.monthly))
        try session.expireSubscription(productIdentifier: VESSPlusView.Plan.monthly.productID)
        #expect(await waitUntil { await !PlusStore.isEntitled() })
    }

    @Test("Ask to Buy is pending and unlocks nothing until approved")
    func askToBuy() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        session.askToBuyEnabled = true
        guard case .pending = try await PlusStore.purchase(try await product(.monthly)) else {
            Issue.record("Not pending"); return
        }
        #expect(await !PlusStore.isEntitled())
        let pending = try #require(session.allTransactions().first { $0.pendingAskToBuyConfirmation })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        #expect(await waitUntil { await PlusStore.isEntitled() })
    }

    // MARK: Helpers

    private func latestTransaction(_ plan: VESSPlusView.Plan, after id: UInt64) async throws -> Transaction {
        for _ in 0..<50 {
            if case .verified(let transaction) = await Transaction.latest(for: plan.productID), transaction.id != id {
                return transaction
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CancellationError()
    }

    /// StoreKit Test applies some changes asynchronously.
    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<50 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
