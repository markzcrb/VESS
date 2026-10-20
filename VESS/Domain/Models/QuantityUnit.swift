import Foundation

/// Units for food servings, logged quantities and inventory.
/// Shared so a pantry item and a logged food describe amounts the same way.
nonisolated enum QuantityUnit: String, Codable, CaseIterable, Sendable {
    case gram
    case kilogram
    case milliliter
    case liter
    case piece
    case pack
    case slice
    case cup
    case tablespoon
    case teaspoon
    case serving
}
