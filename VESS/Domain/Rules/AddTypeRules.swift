import Foundation

/// What the "+" sheet can add (21, 22), in carousel order.
nonisolated enum AddType: String, CaseIterable, Codable, Sendable {
    case photo, quickAdd, food, drink, supplements, workout, habits, weight, cycle
}

/// Which types the carousel shows, and which one the sheet opens on.
nonisolated enum AddTypeRules {
    /// The type used last is reopened for this long.
    static let reopenWindow: TimeInterval = 60 * 60

    /// Photo when offered, Cycle only while tracking is on.
    /// Hidden types leave no gap.
    static func visible(photo: Bool, cycle: Bool) -> [AddType] {
        AddType.allCases.filter { type in
            switch type {
            case .photo: photo
            case .cycle: cycle
            default: true
            }
        }
    }

    /// A type asked for by an entry point wins; then the type used last,
    /// if it was within the past hour and is still shown; otherwise Food.
    static func initial(requested: AddType?, lastUsed: AddType?, lastUsedAt: Date?, now: Date, visible: [AddType]) -> AddType {
        if let requested, visible.contains(requested) { return requested }
        if let lastUsed, let lastUsedAt, visible.contains(lastUsed),
           now.timeIntervalSince(lastUsedAt) >= 0, now.timeIntervalSince(lastUsedAt) <= reopenWindow {
            return lastUsed
        }
        return .food
    }
}
