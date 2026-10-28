#if DEBUG
import StoreKit

/// UMEVA+ and StoreKit 2: entitlement, purchase, restore and the launch-time
/// transaction listener. DEBUG only, like the paywall.
enum PlusStore {
    static var productIDs: Set<String> { Set(VESSPlusView.Plan.allCases.map(\.productID)) }

    /// A verified, current, unrevoked, not upgraded UMEVA+ subscription.
    static func isEntitled(now: Date = .now) async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if PlusEntitlementRules.isActive(productID: transaction.productID, productIDs: productIDs,
                                             revocationDate: transaction.revocationDate,
                                             expirationDate: transaction.expirationDate,
                                             isUpgraded: transaction.isUpgraded, now: now) {
                return true
            }
        }
        return false
    }

    enum PurchaseOutcome {
        case purchased(Transaction)
        /// Ask to Buy, or a payment that needs more steps: nothing yet.
        case pending
        case cancelled
    }

    enum PurchaseError: Error {
        /// The App Store's signature didn't check out; nothing is unlocked.
        case unverified
    }

    /// Buys and finishes a verified transaction.
    static func purchase(_ product: Product) async throws -> PurchaseOutcome {
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw PurchaseError.unverified }
            await transaction.finish()
            return .purchased(transaction)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Restore: syncs with the App Store (it may ask to sign in), then says
    /// whether UMEVA+ is active.
    static func restore() async throws -> Bool {
        try await AppStore.sync()
        return await isEntitled()
    }

    /// From launch: every verified transaction is finished (renewals,
    /// purchases on other devices, approved Ask to Buy, refunds), and the
    /// trial reminder follows the subscription.
    static func listen(_ reminders: ReminderService) async {
        await VESSPlusTrial.reconcileReminder(reminders)
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
            await VESSPlusTrial.reconcileReminder(reminders)
        }
    }
}
#endif
