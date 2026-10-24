import Foundation

/// A food definition: a catalog item, a product from an online database, or
/// a user-created food.
///
/// Nutrition is stored for a reference amount (`servingSize` in `servingUnit`,
/// usually 100 g). Named portions such as "1 slice (30 g)" are expressed in
/// that same unit, so every calculation scales one set of values.
nonisolated struct Food: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    /// The reference amount that `nutrition` describes, such as 100 g.
    var servingSize: Double
    var servingUnit: QuantityUnit
    /// Nutrition for one `servingSize` in `servingUnit`.
    var nutrition: NutritionFacts
    var ingredients: [String]
    var allergens: Set<Allergen>
    var quality: FoodQuality?
    var source: FoodSource
    let createdAt: Date
    var updatedAt: Date
    /// Named portions, in `servingUnit`, for example "1 slice" = 30 g.
    var servingOptions: [ServingOption]? = nil
    /// Where the data came from and when, for remote and catalog foods.
    var sourceInfo: FoodSourceInfo? = nil

    /// Nutrition for `quantity`, expressed in this food's `servingUnit`.
    func nutrition(forQuantity quantity: Double) -> NutritionFacts {
        guard servingSize > 0 else { return .zero }
        return nutrition.scaled(by: quantity / servingSize)
    }

    /// Portions offered when logging: named portions first, then the base unit.
    var portionOptions: [ServingOption] {
        (servingOptions ?? []) + [ServingOption.baseUnit(servingUnit)]
    }

    /// The portion selected by default: the first named portion if any.
    var defaultPortion: Portion {
        if let first = servingOptions?.first {
            return Portion(option: first, count: 1)
        }
        return Portion(option: .baseUnit(servingUnit), count: servingSize)
    }
}

/// A named portion of a food, measured in the food's `servingUnit`.
nonisolated struct ServingOption: Codable, Hashable, Sendable, Identifiable {
    var id: String { "\(label)|\(amount)" }
    /// For example "1 slice" or "1 medium".
    var label: String
    /// Size of one portion in the food's base unit, for example 30 (g).
    var amount: Double
    /// `true` for the plain unit option ("g", "ml"), counted directly.
    var isBaseUnit: Bool = false

    static func baseUnit(_ unit: QuantityUnit) -> ServingOption {
        ServingOption(label: unit.rawValue, amount: 1, isBaseUnit: true)
    }
}

/// What the user chose to log: a count of a portion, such as 1.5 × "1 slice".
nonisolated struct Portion: Hashable, Sendable {
    var option: ServingOption
    var count: Double

    /// The logged amount in the food's base unit.
    var baseAmount: Double { option.amount * count }
}

/// The 14 allergens EU food labels must declare, in the regulation's order.
/// `nuts` are tree nuts; `crustaceans` are shellfish.
nonisolated enum Allergen: String, Codable, CaseIterable, Sendable {
    case gluten
    case crustaceans
    case eggs
    case fish
    case peanuts
    case soy
    case milk
    case nuts
    case celery
    case mustard
    case sesame
    case sulphites
    case lupin
    case molluscs

    /// Earlier builds stored milk as "lactose".
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = raw == "lactose" ? .milk : Allergen(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown allergen \(raw)"))
        }
        self = value
    }
}

/// Where a food's data came from. Estimates and community data are always
/// labeled as such in the UI; only VESS-curated catalog values are "typical".
nonisolated enum FoodSource: String, Codable, Sendable {
    case userCreated
    case foodDatabase
    case barcodeScan
    case aiEstimate
    /// The small built-in catalog of generic foods.
    case starterCatalog
    /// A product retrieved from Open Food Facts (community data).
    case openFoodFacts
    /// Estimated from a photo by the AI processor, then confirmed by the
    /// user. Additive: older entries never carry it.
    case photoEstimate
}

/// Provenance for data that VESS did not author.
nonisolated struct FoodSourceInfo: Codable, Hashable, Sendable {
    /// Human-readable provider, for example "Open Food Facts".
    var provider: String
    /// The provider's identifier, such as a barcode.
    var externalID: String?
    /// When the data was retrieved. Used for cache freshness.
    var retrievedAt: Date?
    /// A page where the user can see or correct the source data.
    var url: URL?
    /// The data license, for attribution.
    var license: String?
    /// `true` when the data is contributed by a community and not verified.
    var isCommunityContributed: Bool
}

/// Ingredient-level quality metadata. Descriptive only, never a health verdict.
nonisolated struct FoodQuality: Codable, Hashable, Sendable {
    var processingLevel: ProcessingLevel?
    var additives: [String]
}

/// Degree of processing, aligned with the NOVA classification groups.
nonisolated enum ProcessingLevel: String, Codable, CaseIterable, Sendable {
    case unprocessed
    case processedIngredient
    case processed
    case ultraProcessed
}
