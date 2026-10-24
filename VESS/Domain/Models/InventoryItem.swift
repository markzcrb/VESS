import Foundation

/// Something the user has at home (the "PantryItem" in the product spec).
nonisolated struct InventoryItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// `nil` when the amount isn't known (shown as "some"), such as a
    /// recipe ingredient bought without an amount.
    var quantity: Double?
    var unit: QuantityUnit
    var purchaseDate: Date?
    var expirationDate: Date?
    var category: InventoryCategory
    var location: StorageLocation
    var notes: String?
    var status: InventoryStatus
    /// When set, expiration reminders are paused until this date.
    var reminderSnoozedUntil: Date?
    /// The USDA food the user chose for this item's nutrition (NDB number),
    /// so it is picked only once. `nil`: matched by name.
    var genericFoodID: String? = nil

    func expirationStatus(now: Date, calendar: Calendar) -> ExpirationStatus {
        ExpirationStatus(expirationDate: expirationDate, now: now, calendar: calendar)
    }
}

nonisolated enum StorageLocation: String, Codable, CaseIterable, Sendable {
    case fridge
    case freezer
    case pantry
    case other
}

nonisolated enum InventoryCategory: String, Codable, CaseIterable, Sendable {
    case protein
    case vegetables
    case fruit
    case carbohydrates
    case dairy
    case drinks
    case snacks
    case supplements
    case other
}

/// Items leave the active inventory as consumed or discarded. Both are kept
/// for food-waste insights.
nonisolated enum InventoryStatus: String, Codable, Sendable {
    case available
    case consumed
    case discarded
}

/// How soon an item expires, by calendar day.
nonisolated enum ExpirationStatus: Hashable, Sendable {
    case noDate
    case expired(daysAgo: Int)
    case today
    case tomorrow
    /// Two or more days away, up to and including `soonThresholdDays`.
    case soon(days: Int)
    case later(days: Int)

    /// Days ahead that still count as "Expiring soon".
    static let soonThresholdDays = 3

    init(expirationDate: Date?, now: Date, calendar: Calendar) {
        guard let expirationDate else {
            self = .noDate
            return
        }
        let today = calendar.startOfDay(for: now)
        let expirationDay = calendar.startOfDay(for: expirationDate)
        let days = calendar.dateComponents([.day], from: today, to: expirationDay).day ?? 0

        switch days {
        case ..<0: self = .expired(daysAgo: -days)
        case 0: self = .today
        case 1: self = .tomorrow
        case 2...Self.soonThresholdDays: self = .soon(days: days)
        default: self = .later(days: days)
        }
    }

    /// Whether this belongs in the Today screen's "Expiring soon" section.
    var needsAttention: Bool {
        switch self {
        case .expired, .today, .tomorrow, .soon: true
        case .noDate, .later: false
        }
    }
}
