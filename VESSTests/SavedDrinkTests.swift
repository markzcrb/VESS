import Foundation
import Testing
@testable import VESS

@Suite("Saved drinks")
struct SavedDrinkTests {
    @Test("A saved drink logs its own size, water share and caffeine")
    func logs() {
        let saved = SavedDrink(id: UUID(), name: "Oat flat white", basedOn: .flatWhite,
                               volumeMilliliters: 240, hydrationContributionPercent: 70, caffeineMilligrams: 120)
        let drink = saved.drink()
        #expect(drink.name == "Oat flat white" && drink.type == DrinkPreset.flatWhite.type)
        let log = drink.log(userID: UUID(), volumeMilliliters: 240, at: .now)
        #expect(abs(log.caffeineMilligrams - 120) < 0.01)
        #expect(abs(log.hydrationMilliliters - 168) < 0.01)
    }

    @Test("Profiles from before decode without saved drinks; saved drinks round-trip")
    func storage() throws {
        var profile = MockData(now: .now, calendar: TestClock.utc).profile
        #expect(profile.savedDrinks == nil)
        profile.savedDrinks = [SavedDrink(id: UUID(), name: "Matcha latte", basedOn: .matcha,
                                          volumeMilliliters: 300, hydrationContributionPercent: 80, caffeineMilligrams: 70)]
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded.savedDrinks == profile.savedDrinks)
    }
}
