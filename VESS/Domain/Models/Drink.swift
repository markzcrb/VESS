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
            loggedAt: date
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

/// The groups on the drink sheet's chips (reference 10).
nonisolated enum DrinkCategory: String, CaseIterable, Sendable {
    case water
    case tea
    case coffee
    case other

    /// The drinks in this group, in the order they're offered.
    var presets: [DrinkPreset] {
        DrinkPreset.allCases.filter { $0.category == self }
    }
}

/// Built-in drinks offered when logging. Nutrition values are typical
/// figures for a standard preparation and are labeled as such in the UI.
nonisolated enum DrinkPreset: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case water
    case sparklingWater
    case blackCoffee
    case flatWhite
    case tea
    case juice
    case softDrink
    case other

    var type: DrinkType {
        switch self {
        case .water, .sparklingWater: .water
        case .blackCoffee, .flatWhite: .coffee
        case .tea: .tea
        case .juice: .juice
        case .softDrink: .softDrink
        case .other: .custom
        }
    }

    var category: DrinkCategory {
        switch self {
        case .water, .sparklingWater: .water
        case .tea: .tea
        case .blackCoffee, .flatWhite: .coffee
        case .juice, .softDrink, .other: .other
        }
    }

    var defaultVolumeMilliliters: Double {
        switch self {
        case .water, .tea, .juice, .other: 250
        case .sparklingWater, .softDrink: 330
        case .blackCoffee: 200
        case .flatWhite: 240
        }
    }

    /// Per-drink default. A milk coffee counts slightly less than black
    /// coffee; a 240 ml flat white counts as about 190 ml.
    var defaultHydrationContributionPercent: Double {
        switch self {
        case .blackCoffee: 90
        case .flatWhite: 79
        default: type.defaultHydrationContributionPercent
        }
    }

    /// Typical calories, sugar (g) and caffeine (mg) per 100 ml.
    private var typicalPer100Milliliters: (calories: Double, sugar: Double, caffeine: Double) {
        switch self {
        case .water, .sparklingWater, .other: (0, 0, 0)
        case .blackCoffee: (1, 0, 40)
        case .flatWhite: (46, 4.5, 54)
        case .tea: (1, 0, 20)
        case .juice: (45, 9, 0)
        case .softDrink: (42, 10.6, 10)
        }
    }

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
            hydrationContributionPercent: hydrationContributionPercent ?? defaultHydrationContributionPercent
        )
    }
}
