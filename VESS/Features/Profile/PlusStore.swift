import StoreKit

/// UMEVA+ and StoreKit 2: purchase, restore, the launch-time transaction
/// listener and the signed transactions the server checks. What UMEVA+
/// unlocks comes from the server (`PlanStore`), never from here.
enum PlusStore {
    static var productIDs: Set<String> { Set(VESSPlusView.Plan.allCases.map(\.productID)) }

    /// The JWS of each verified, current UMEVA+ entitlement, for the
    /// `entitlement` function to verify with Apple.
    static func signedEntitlements(now: Date = .now) async -> [String] {
        var signed: [String] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PlusEntitlementRules.isActive(productID: transaction.productID, productIDs: productIDs,
                                                revocationDate: transaction.revocationDate,
                                                expirationDate: transaction.expirationDate,
                                                isUpgraded: transaction.isUpgraded, now: now) else { continue }
            signed.append(result.jwsRepresentation)
        }
        return signed
    }

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

    /// Buys for this UMEVA account (`appAccountToken` = the Supabase user
    /// id, which the server checks) and finishes a verified transaction.
    static func purchase(_ product: Product, accountToken: UUID) async throws -> PurchaseOutcome {
        switch try await product.purchase(options: [.appAccountToken(accountToken)]) {
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

    /// Restore: syncs with the App Store (it may ask to sign in); the
    /// caller then asks the server.
    static func restore() async throws -> Bool {
        try await AppStore.sync()
        return await isEntitled()
    }

    /// From launch: every verified transaction is finished (renewals,
    /// purchases on other devices, approved Ask to Buy, refunds), and the
    /// trial reminder follows the subscription.
    static func listen(_ reminders: ReminderService, plan: PlanStore) async {
        await VESSPlusTrial.reconcileReminder(reminders)
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
            await VESSPlusTrial.reconcileReminder(reminders)
            await plan.sync()
        }
    }
}
