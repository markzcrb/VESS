import Foundation
import Testing
@testable import VESS

@Suite("Drink catalog")
struct DrinkCatalogTests {
    private let userID = UUID()
    private let calendar = TestClock.utc
    private let targets = NutritionTargets(calories: 2000, proteinGrams: 100, carbohydrateGrams: 250, fatGrams: 70)

    @Test("Every drink has a chip; alcohol counts 0 % toward water")
    func categories() {
        for preset in DrinkPreset.allCases {
            #expect(preset.category.presets.contains(preset))
        }
        #expect(DrinkCategory.coffee.presets == [.espresso, .americano, .cappuccino, .latte, .flatWhite, .blackCoffee, .coldBrew])
        #expect(DrinkCategory.tea.presets == [.tea, .greenTea, .herbalTea])
        #expect(DrinkCategory.alcohol.presets == [.beer, .wine, .spirit, .cocktail])
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
        #expect(water.alcoholGrams == nil && water.energyCalories == 0)
    }

    @Test("Alcohol's kcal count in the day's energy but never raise Fuel")
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
        #expect(abs(both.consumed.calories - (1200 + wine.calories)) < 0.001, "Wine counts; a latte's kcal still don't")
        #expect(both.alcoholCalories == wine.calories)
        #expect(both.foodCalories == 1200)

        // The latte's water share raises hydration (as drinks always have),
        // so Fuel is compared with and without the wine alone.
        let fuelWithout = try #require(FuelScore(summary: summary([]), hasLoggedFood: true, regularity: nil))
        let fuelWithWine = try #require(FuelScore(summary: summary([wine]), hasLoggedFood: true, regularity: nil))
        #expect(fuelWithWine.value == fuelWithout.value, "Drinking never raises Fuel")
        #expect(fuelWithWine.components.energy == fuelWithout.components.energy)
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
        let extra = [beer, yesterdayWine].alcoholEnergy

        let points = IntakeAnalysis.cumulative([breakfast], extra: [beer].alcoholEnergy, calendar: calendar)
        #expect(points.map(\.minute) == [8 * 60, 19 * 60])
        #expect(abs((points.last?.calories ?? 0) - (400 + beer.calories)) < 0.001)

        let share = try #require(IntakeAnalysis.beforeNoonShare([breakfast], extra: [beer].alcoholEnergy, calendar: calendar))
        #expect(abs(share - 400 / (400 + beer.calories)) < 0.0001)

        let week = IntakeAnalysis.dailyTotals([breakfast], extra: extra, endingOn: day, days: 2, calendar: calendar)
        #expect(week[0].hasEntries, "A day with only a drink still counts as logged")
        #expect(abs(week[0].nutrition.calories - yesterdayWine.calories) < 0.001)
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
