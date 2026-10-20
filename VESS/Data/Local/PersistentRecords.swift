import Foundation
import SwiftData

// SwiftData records for on-device storage.
//
// Each record keeps the fields needed for querying (id, date) as columns and
// the full domain value as JSON in `payload`. The domain types stay plain
// value types with no persistence dependency, and the same Codable form will
// be used for cloud sync later. New optional domain fields need no migration.

@Model
final class StoredProfile {
    @Attribute(.unique) var id: UUID
    var payload: Data

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

@Model
final class StoredFoodLogEntry {
    @Attribute(.unique) var id: UUID
    var loggedAt: Date
    var payload: Data

    init(id: UUID, loggedAt: Date, payload: Data) {
        self.id = id
        self.loggedAt = loggedAt
        self.payload = payload
    }
}

/// A food saved on this device: user-created, cached from an online
/// provider, or a catalog food the user marked as a favorite.
@Model
final class StoredFood {
    @Attribute(.unique) var id: UUID
    /// Normalized name and brand, for search (see `FoodSearch.normalized`).
    var searchKey: String
    var barcode: String?
    var isFavorite: Bool
    var updatedAt: Date
    var payload: Data

    init(id: UUID, searchKey: String, barcode: String?, isFavorite: Bool, updatedAt: Date, payload: Data) {
        self.id = id
        self.searchKey = searchKey
        self.barcode = barcode
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
        self.payload = payload
    }
}

@Model
final class StoredHydrationLog {
    @Attribute(.unique) var id: UUID
    var loggedAt: Date
    var payload: Data

    init(id: UUID, loggedAt: Date, payload: Data) {
        self.id = id
        self.loggedAt = loggedAt
        self.payload = payload
    }
}

/// Something at home (Pantry). Added in the redesign; an additive entity,
/// so stores from earlier builds open unchanged.
@Model
final class StoredInventoryItem {
    @Attribute(.unique) var id: UUID
    var expirationDate: Date?
    /// `false` once used up or thrown away; kept for food-waste insights.
    var isActive: Bool
    var payload: Data

    init(id: UUID, expirationDate: Date?, isActive: Bool, payload: Data) {
        self.id = id
        self.expirationDate = expirationDate
        self.isActive = isActive
        self.payload = payload
    }
}

/// A meal planned for a day (Plan). Additive, like `StoredInventoryItem`.
@Model
final class StoredPlannedMeal {
    @Attribute(.unique) var id: UUID
    /// The start of the planned day, for week queries.
    var day: Date
    var payload: Data

    init(id: UUID, day: Date, payload: Data) {
        self.id = id
        self.day = day
        self.payload = payload
    }
}

/// What the user added to or changed on the grocery list. Additive.
@Model
final class StoredGroceryItem {
    @Attribute(.unique) var id: UUID
    var payload: Data

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}
