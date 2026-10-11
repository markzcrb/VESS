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
