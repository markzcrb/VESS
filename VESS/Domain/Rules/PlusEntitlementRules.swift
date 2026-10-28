import Foundation

/// Whether a verified transaction unlocks UMEVA+: one of its products, not
/// refunded or revoked, not expired, and not replaced by an upgrade. Pure.
nonisolated enum PlusEntitlementRules {
    static func isActive(productID: String, productIDs: Set<String>, revocationDate: Date?,
                         expirationDate: Date?, isUpgraded: Bool, now: Date) -> Bool {
        guard productIDs.contains(productID), revocationDate == nil, !isUpgraded,
              let expirationDate else { return false }
        return expirationDate > now
    }
}
