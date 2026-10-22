import Foundation

/// A drink definition. Nutrition values are per 100 ml so any volume can be logged.
///
/// Hydration is tracked separately from nutrition: `hydrationContributionPercent`
/// is the share of the volume counted toward the daily water target. It is a
/// user-adjustable estimate, not a measurement, and never changes the drink's
/// volume, calories or nutrients.
nonisolated struct Drink: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var type: DrinkType
    var defaultVolumeMilliliters: Double
    var caloriesPer100Milliliters: Double
    var sugarGramsPer100Milliliters: Double
    var caffeineMilligramsPer100Milliliters: Double
    /// 0–100. Defaults from `DrinkType`; the user can change it.
    var hydrationContributionPercent: Double
    /// Grams of pure alcohol per 100 ml; 0 for drinks without alcohol.
    var alcoholGramsPer100Milliliters: Double = 0

    /// Creates a hydration log for `volumeMilliliters` of this drink.
    /// Pass `hydrationContributionPercent` to override the drink's default for this log.
    func log(
        id: UUID = UUID(),
        userID: UUID,
        volumeMilliliters: Double,
        hydrationContributionPercent: Double? = nil,
        at date: Date
    ) -> HydrationLog {
        let factor = volumeMilliliters / 100
        return HydrationLog(
            id: id,
            userID: userID,
            drinkID: self.id,
            drinkName: name,
            drinkType: type,
            volumeMilliliters: volumeMilliliters,
            hydrationContributionPercent: hydrationContributionPercent ?? self.hydrationContributionPercent,
            calories: caloriesPer100Milliliters * factor,
            sugarGrams: sugarGramsPer100Milliliters * factor,
            caffeineMilligrams: caffeineMilligramsPer100Milliliters * factor,
            loggedAt: date,
            alcoholGrams: alcoholGramsPer100Milliliters > 0 ? alcoholGramsPer100Milliliters * factor : nil
        )
    }
}

nonisolated enum DrinkType: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case water
    case coffee
    case tea
    case juice
    case softDrink
    case energyDrink
    case alcohol
    case custom

    /// Starting value for `Drink.hydrationContributionPercent`. These are
    /// conservative tracking defaults that users can adjust, not health claims.
    var defaultHydrationContributionPercent: Double {
        switch self {
        case .water: 100
        case .tea: 90
        case .juice: 85
        case .coffee: 80
        case .softDrink: 70
        case .custom: 75
        case .energyDrink: 60
        case .alcohol: 0
        }
    }
}

/// The groups on the drink sheet's chips: reference 10's four, plus Alcohol.
nonisolated enum DrinkCategory: String, CaseIterable, Sendable {
    case water
    case tea
    case coffee
    case other
    case alcohol

    /// The drinks in this group, in the order they're offered.
    var presets: [DrinkPreset] {
        DrinkPreset.allCases.filter { $0.category == self }
    }
}

/// Grams of pure alcohol in a "drink" (a standard drink of 10 g).
nonisolated enum StandardDrink {
    static let grams = 10.0
    /// Density of ethanol, g/ml, to turn % by volume into grams.
    static let ethanolDensity = 0.789

    static func count(alcoholGrams: Double) -> Double {
        alcoholGrams / grams
    }

    /// Grams of alcohol per 100 ml at `percentByVolume`.
    static func gramsPer100Milliliters(percentByVolume: Double) -> Double {
        percentByVolume * ethanolDensity
    }
}

/// Built-in drinks offered when logging. Nutrition values are typical
/// figures for a standard preparation and are labeled as such in the UI.
///
/// Raw values are stored (the user's own hydration shares are keyed by
/// them), so existing cases keep their names; new cases are appended in
/// meaning only, and `allCases` order is the order they're offered.
nonisolated enum DrinkPreset: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    // Water
    case water
    case sparklingWater
    // Coffee
    case espresso
    case americano
    case cappuccino
    case latte
    case flatWhite
    /// Drip (filter) coffee. Stored as `blackCoffee`, its earlier name.
    case blackCoffee
    case coldBrew
    // Tea
    /// Black tea. Stored as `tea`, its earlier name.
    case tea
    case greenTea
    case herbalTea
    // Other
    case juice
    case softDrink
    case cola
    case energyDrink
    case other
    // Alcohol
    case beer
    case wine
    case spirit
    case cocktail

    var type: DrinkType {
        switch self {
        case .water, .sparklingWater: .water
        case .espresso, .americano, .cappuccino, .latte, .flatWhite, .blackCoffee, .coldBrew: .coffee
        case .tea, .greenTea, .herbalTea: .tea
        case .juice: .juice
        case .softDrink, .cola: .softDrink
        case .energyDrink: .energyDrink
        case .other: .custom
        case .beer, .wine, .spirit, .cocktail: .alcohol
        }
    }

    var category: DrinkCategory {
        switch type {
        case .water: .water
        case .tea: .tea
        case .coffee: .coffee
        case .alcohol: .alcohol
        case .juice, .softDrink, .energyDrink, .custom: .other
        }
    }

    var defaultVolumeMilliliters: Double {
        switch self {
        case .water, .tea, .juice, .other: 250
        case .sparklingWater, .softDrink: 330
        case .blackCoffee: 200
        case .flatWhite: 240
        // Typical serving sizes (new presets).
        case .espresso: 30
        case .americano, .coldBrew, .greenTea, .herbalTea, .energyDrink: 250
        case .cappuccino: 180
        case .latte: 300
        case .cola, .beer: 330
        case .wine, .cocktail: 150
        case .spirit: 40
        }
    }

    /// Per-drink default. A milk coffee counts slightly less than black
    /// coffee; a 240 ml flat white counts as about 190 ml. Other drinks use
    /// their type's default (alcohol counts 0 %).
    var defaultHydrationContributionPercent: Double {
        switch self {
        case .blackCoffee: 90
        case .flatWhite: 79
        default: type.defaultHydrationContributionPercent
        }
    }

    /// Whether this preset's kcal, sugar, caffeine or alcohol figures are
    /// typical values added with the expanded catalog rather than taken
    /// from the earlier catalog. All figures are shown as typical values.
    var hasNewTypicalValues: Bool {
        switch self {
        case .water, .sparklingWater, .blackCoffee, .flatWhite, .tea, .juice, .softDrink, .other: false
        default: true
        }
    }

    /// Typical calories, sugar (g), caffeine (mg) and alcohol (g) per 100 ml.
    /// The first group is the earlier catalog; the rest are typical values
    /// for a standard preparation, listed in the drinks summary.
    private var typicalPer100Milliliters: (calories: Double, sugar: Double, caffeine: Double, alcohol: Double) {
        switch self {
        // Earlier catalog.
        case .water, .sparklingWater, .other: (0, 0, 0, 0)
        case .blackCoffee: (1, 0, 40, 0)
        case .flatWhite: (46, 4.5, 54, 0)
        case .tea: (1, 0, 20, 0)
        case .juice: (45, 9, 0, 0)
        case .softDrink: (42, 10.6, 10, 0)
        // Typical values. Coffees assume a double shot (126 mg) where milk is added.
        case .espresso: (9, 0, 212, 0)
        case .americano: (1, 0, 50, 0)
        case .cappuccino: (38, 3.5, 70, 0)
        case .latte: (54, 5, 42, 0)
        case .coldBrew: (2, 0, 45, 0)
        case .greenTea: (1, 0, 12, 0)
        case .herbalTea: (1, 0, 0, 0)
        case .cola: (42, 10.6, 10, 0)
        case .energyDrink: (45, 11, 32, 0)
        // Alcohol by volume: beer 5 %, wine 12 %, spirit 40 %; a cocktail as
        // one 40 ml shot of a 40 % spirit in 150 ml.
        case .beer: (43, 0, 0, StandardDrink.gramsPer100Milliliters(percentByVolume: 5))
        case .wine: (83, 0.8, 0, StandardDrink.gramsPer100Milliliters(percentByVolume: 12))
        case .spirit: (231, 0, 0, StandardDrink.gramsPer100Milliliters(percentByVolume: 40))
        case .cocktail: (100, 8, 0, StandardDrink.gramsPer100Milliliters(percentByVolume: 40) * 40 / 150)
        }
    }

    /// Caffeine in mg per 100 ml, for the caffeine screen's quick-log grid.
    var caffeineMilligramsPer100Milliliters: Double { typicalPer100Milliliters.caffeine }

    /// A drink definition for this preset, using `hydrationContributionPercent`
    /// if the user has set their own default.
    func drink(name: String, hydrationContributionPercent: Double? = nil) -> Drink {
        let typical = typicalPer100Milliliters
        return Drink(
            id: UUID(),
            name: name,
            type: type,
            defaultVolumeMilliliters: defaultVolumeMilliliters,
            caloriesPer100Milliliters: typical.calories,
            sugarGramsPer100Milliliters: typical.sugar,
            caffeineMilligramsPer100Milliliters: typical.caffeine,
            hydrationContributionPercent: hydrationContributionPercent ?? defaultHydrationContributionPercent,
            alcoholGramsPer100Milliliters: typical.alcohol
        )
    }
}
