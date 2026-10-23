import Foundation
import Testing
@testable import VESS

@Suite("Drink catalog")
struct DrinkCatalogTests {
    private let userID = UUID()
    private let calendar = TestClock.utc
    private let targets = NutritionTargets(calories: 2000, proteinGrams: 100, carbohydrateGrams: 250, fatGrams: 70)

    @Test("Every offered drink sits in its own category, in the order of 19 and 20; alcohol counts 0 % toward water")
    func categories() {
        // Cola and "Other drink" are no longer offered; their logs still decode.
        for preset in DrinkPreset.allCases where ![.cola, .other].contains(preset) {
            #expect(preset.category.presets.contains(preset), "\(preset) is offered")
        }
        #expect(DrinkCategory.water.presets == [.water, .sparklingWater])
        #expect(DrinkCategory.tea.presets == [.greenTea, .tea, .herbalTea, .matcha])
        #expect(DrinkCategory.coffee.presets == [.espresso, .americano, .latte, .cappuccino, .flatWhite, .blackCoffee, .coldBrew, .instantCoffee, .decaf])
        #expect(DrinkCategory.other.presets == [.juice, .softDrink, .energyDrink, .milk, .smoothie, .sportsDrink, .kombucha])
        #expect(DrinkCategory.alcohol.presets == [.beer, .wine, .spirit, .cocktail, .cider])
        for category in DrinkCategory.allCases {
            #expect(category.presets.allSatisfy { $0.category == category })
        }
        for preset in DrinkCategory.alcohol.presets {
            #expect(preset.defaultHydrationContributionPercent == 0)
            #expect(DrinkFacts.contributionPercent(preset, profile: nil) == 0)
        }
    }

    @Test("The earlier catalog's values are unchanged")
    func earlierValues() {
        let drip = DrinkPreset.blackCoffee.drink(name: "")
        #expect(drip.caffeineMilligramsPer100Milliliters == 40 && drip.hydrationContributionPercent == 90)
        let flatWhite = DrinkPreset.flatWhite.drink(name: "")
        #expect(flatWhite.caloriesPer100Milliliters == 46 && flatWhite.caffeineMilligramsPer100Milliliters == 54)
        #expect(flatWhite.hydrationContributionPercent == 79)
        #expect(DrinkPreset.tea.drink(name: "").caffeineMilligramsPer100Milliliters == 20)
        #expect(DrinkPreset.softDrink.drink(name: "").caffeineMilligramsPer100Milliliters == 10)
        // New drinks without their own share use their type's existing default.
        #expect(DrinkPreset.latte.defaultHydrationContributionPercent == 80)
        #expect(DrinkPreset.greenTea.defaultHydrationContributionPercent == 90)
    }

    @Test("Alcohol is grams of pure alcohol and drinks of 10 g; it adds nothing toward water")
    func alcohol() throws {
        let now = try TestClock.date(2026, 10, 6, 19, 0)
        let beer = DrinkPreset.beer.drink(name: "Beer").log(userID: userID, volumeMilliliters: 330, at: now)
        let grams = try #require(beer.alcoholGrams)
        #expect(abs(grams - 13.0) < 0.05, "330 ml at 5 % is about 13 g")
        #expect(abs((beer.standardDrinks ?? 0) - 1.3) < 0.01)
        #expect(beer.hydrationMilliliters == 0)
        #expect(abs(beer.energyCalories - 141.9) < 0.1)

        let spirit = DrinkPreset.spirit.drink(name: "Spirit").log(userID: userID, volumeMilliliters: 40, at: now)
        #expect(abs((spirit.alcoholGrams ?? 0) - 12.6) < 0.05)
        let water = DrinkPreset.water.drink(name: "Water").log(userID: userID, volumeMilliliters: 500, at: now)
        #expect(water.alcoholGrams == nil && water.energyCalories == 0 && water.alcoholCalories == 0)
        let latte = DrinkPreset.latte.drink(name: "Latte").log(userID: userID, volumeMilliliters: 300, at: now)
        #expect(latte.energyCalories == latte.calories && latte.alcoholCalories == 0)
    }

    @Test("Every drink's kcal count in the day's energy; alcohol's never raise Fuel, other drinks' do")
    func energyNotFuel() throws {
        let now = try TestClock.date(2026, 10, 6, 20, 0)
        let lunch = FoodLogEntry(
            id: UUID(), userID: userID, foodID: nil, foodName: "Lunch", mealType: .lunch,
            quantity: 1, servingUnit: .serving,
            nutrition: NutritionFacts(calories: 1200, proteinGrams: 60, carbohydrateGrams: 0, fatGrams: 0),
            loggedAt: try TestClock.date(2026, 10, 6, 12, 30)
        )
        let wine = DrinkPreset.wine.drink(name: "Wine").log(userID: userID, volumeMilliliters: 150, at: now)
        let latte = DrinkPreset.latte.drink(name: "Latte").log(userID: userID, volumeMilliliters: 300, at: now)

        func summary(_ drinks: [HydrationLog]) -> DaySummary {
            DaySummary(entries: [lunch], hydrationLogs: drinks, targets: targets, waterTargetMilliliters: 2000, day: now, now: now, calendar: calendar)
        }
        let both = summary([wine, latte])
        #expect(abs(both.consumed.calories - (1200 + wine.calories + latte.calories)) < 0.001, "Wine and the latte both count in energy")
        #expect(both.alcoholCalories == wine.calories)
        #expect(abs(both.drinkCalories - (wine.calories + latte.calories)) < 0.001)
        #expect(abs(both.fuelCalories - (1200 + latte.calories)) < 0.001, "Fuel counts the latte, not the wine")

        // The latte's water share raises hydration (as drinks always have),
        // so Fuel is compared with and without the wine alone.
        let fuelWithout = try #require(FuelScore(summary: summary([]), hasLoggedFood: true, regularity: nil))
        let fuelWithWine = try #require(FuelScore(summary: summary([wine]), hasLoggedFood: true, regularity: nil))
        #expect(fuelWithWine.value == fuelWithout.value, "Drinking never raises Fuel")
        #expect(fuelWithWine.components.energy == fuelWithout.components.energy)

        // A non-alcoholic drink's kcal do raise Fuel's energy part.
        let juice = DrinkPreset.juice.drink(name: "Juice").log(userID: userID, volumeMilliliters: 1000, at: now)
        let fuelWithJuice = try #require(FuelScore(summary: summary([juice]), hasLoggedFood: true, regularity: nil))
        #expect(fuelWithJuice.components.energy > fuelWithout.components.energy)
    }

    @Test("The Energy screen's chart, before-noon share and week include alcohol")
    func energyScreen() throws {
        let day = try TestClock.date(2026, 10, 6, 0, 0)
        let breakfast = FoodLogEntry(
            id: UUID(), userID: userID, foodID: nil, foodName: "Oats", mealType: .breakfast,
            quantity: 1, servingUnit: .serving,
            nutrition: NutritionFacts(calories: 400, proteinGrams: 10, carbohydrateGrams: 0, fatGrams: 0),
            loggedAt: try TestClock.date(2026, 10, 6, 8, 0)
        )
        let beer = DrinkPreset.beer.drink(name: "Beer").log(userID: userID, volumeMilliliters: 330, at: try TestClock.date(2026, 10, 6, 19, 0))
        let yesterdayWine = DrinkPreset.wine.drink(name: "Wine").log(userID: userID, volumeMilliliters: 150, at: try TestClock.date(2026, 10, 5, 20, 0))
        let extra = [beer, yesterdayWine].drinkEnergy

        let points = IntakeAnalysis.cumulative([breakfast], extra: [beer].drinkEnergy, calendar: calendar)
        #expect(points.map(\.minute) == [8 * 60, 19 * 60])
        #expect(abs((points.last?.calories ?? 0) - (400 + beer.calories)) < 0.001)

        let share = try #require(IntakeAnalysis.beforeNoonShare([breakfast], extra: [beer].drinkEnergy, calendar: calendar))
        #expect(abs(share - 400 / (400 + beer.calories)) < 0.0001)

        let week = IntakeAnalysis.dailyTotals([breakfast], extra: extra, endingOn: day, days: 2, calendar: calendar)
        #expect(week[0].hasEntries, "A day with only a drink still counts as logged")
        #expect(abs(week[0].nutrition.calories - yesterdayWine.calories) < 0.001)
    }

    @Test("Three sizes per drink, small to large; the middle one is selected")
    func servings() {
        for preset in DrinkPreset.allCases {
            let sizes = preset.servings.map(\.milliliters)
            #expect(sizes.count == 3, "\(preset)")
            #expect(sizes == sizes.sorted() && Set(sizes).count == 3, "\(preset) ascends")
            #expect(preset.selectedServing == preset.servings[1])
        }
        #expect(DrinkPreset.latte.servings.map(\.milliliters) == [250, 350, 450])
        #expect(DrinkPreset.espresso.servings.map(\.milliliters) == [30, 60, 110])
        #expect(DrinkPreset.wine.servings.map(\.milliliters) == [125, 150, 250])
        #expect(DrinkPreset.beer.servings.map(\.milliliters) == [330, 500, 568])
        #expect(DrinkPreset.water.servings.map(\.milliliters) == [250, 330, 500])
    }

    @Test("New drinks keep the existing water shares; cider is alcohol")
    func newDrinks() {
        #expect(DrinkPreset.milk.defaultHydrationContributionPercent == DrinkType.juice.defaultHydrationContributionPercent)
        #expect(DrinkPreset.kombucha.defaultHydrationContributionPercent == DrinkType.softDrink.defaultHydrationContributionPercent)
        #expect(DrinkPreset.matcha.type == .tea && DrinkPreset.decaf.type == .coffee)
        #expect(DrinkPreset.cider.type == .alcohol && DrinkPreset.cider.defaultPercentByVolume == 4.5)
        #expect(DrinkFacts.contributionPercent(.cider, profile: nil) == 0)
        #expect(DrinkPreset.latte.defaultPercentByVolume == nil)
    }

    @Test("Strength: grams of alcohol follow the ABV, and kcal at 7 per gram on top of the drink's other kcal")
    func strength() throws {
        let typical = DrinkPreset.wine.drink(name: "Wine")
        let same = DrinkPreset.wine.drink(name: "Wine", percentByVolume: 12)
        #expect(abs(same.caloriesPer100Milliliters - typical.caloriesPer100Milliliters) < 0.001)
        #expect(abs(same.alcoholGramsPer100Milliliters - typical.alcoholGramsPer100Milliliters) < 0.001)

        let stronger = DrinkPreset.wine.drink(name: "Wine", percentByVolume: 14)
        let extraGrams = 2 * StandardDrink.ethanolDensity
        #expect(abs(stronger.alcoholGramsPer100Milliliters - typical.alcoholGramsPer100Milliliters - extraGrams) < 0.001)
        #expect(abs(stronger.caloriesPer100Milliliters - typical.caloriesPer100Milliliters - extraGrams * 7) < 0.001)

        // Strength is ignored for drinks without alcohol.
        let latte = DrinkPreset.latte.drink(name: "Latte", percentByVolume: 10)
        #expect(latte.alcoholGramsPer100Milliliters == 0)
        let log = stronger.log(userID: userID, volumeMilliliters: 150, at: try TestClock.date(2026, 10, 6, 20))
        #expect(log.hydrationMilliliters == 0)
    }

    @Test("Editing a logged drink scales its values; the share toward water stays")
    func edited() throws {
        let at = try TestClock.date(2026, 10, 6, 9)
        let later = try TestClock.date(2026, 10, 6, 10)
        let latte = DrinkPreset.latte.drink(name: "Latte").log(userID: userID, volumeMilliliters: 300, at: at)
        let bigger = latte.edited(volumeMilliliters: 450, loggedAt: later)
        #expect(bigger.id == latte.id && bigger.loggedAt == later)
        #expect(abs(bigger.caffeineMilligrams - latte.caffeineMilligrams * 1.5) < 0.001)
        #expect(abs(bigger.calories - latte.calories * 1.5) < 0.001)
        #expect(bigger.hydrationContributionPercent == latte.hydrationContributionPercent)
        #expect(abs(bigger.hydrationMilliliters - 360) < 0.001)

        let beer = DrinkPreset.beer.drink(name: "Beer").log(userID: userID, volumeMilliliters: 330, at: at)
        #expect(abs((beer.edited(volumeMilliliters: 660, loggedAt: at).alcoholGrams ?? 0) - (beer.alcoholGrams ?? 0) * 2) < 0.001)
        #expect(DrinkPreset.water.drink(name: "Water").log(userID: userID, volumeMilliliters: 250, at: at)
            .edited(volumeMilliliters: 500, loggedAt: at).alcoholGrams == nil)
    }

    @Test("Logs and profiles saved before the expanded catalog still decode")
    func oldData() throws {
        let log = DrinkPreset.tea.drink(name: "Tea").log(userID: userID, volumeMilliliters: 250, at: try TestClock.date(2026, 10, 6, 9, 0))
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(log)) as? [String: Any])
        json.removeValue(forKey: "alcoholGrams")
        let decoded = try JSONDecoder().decode(HydrationLog.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.alcoholGrams == nil && decoded.volumeMilliliters == 250)

        // The user's own shares are keyed by the earlier raw values.
        let overrides = try JSONDecoder().decode([DrinkPreset: Double].self, from: Data(#"{"blackCoffee": 85, "tea": 95}"#.utf8))
        #expect(overrides[.blackCoffee] == 85 && overrides[.tea] == 95)
    }
}
