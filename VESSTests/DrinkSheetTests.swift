import Foundation
import Testing
@testable import VESS

@Suite("Drink sheet")
@MainActor
struct DrinkSheetTests {
    @Test("Size chips per drink and the stepper's step")
    func sizes() {
        #expect(DrinkFacts.sizes(for: .espresso) == [30, 60, 110])
        #expect(DrinkFacts.sizes(for: .blackCoffee) == [150, 250, 350])
        #expect(DrinkFacts.sizes(for: .water) == [250, 330, 500, 750])
        #expect(DrinkFacts.sizes(for: .tea) == DrinkPreset.tea.servings.map(\.milliliters))
        #expect(DrinkFacts.step(for: .espresso) == 10 && DrinkFacts.step(for: .water) == 50)
        #expect(DrinkFacts.sheetPresets.first == .water && DrinkFacts.sheetPresets.count == 7)
    }

    @Test("The size used last is remembered per drink; otherwise one of its chips")
    func remembered() {
        var stored = ""
        stored = DrinkFacts.remembering(60, for: .espresso, in: stored)
        stored = DrinkFacts.remembering(500, for: .water, in: stored)
        #expect(DrinkFacts.rememberedSize(for: .espresso, in: stored) == 60)
        #expect(DrinkFacts.rememberedSize(for: .water, in: stored) == 500)
        #expect(DrinkFacts.sizes(for: .blackCoffee).contains(DrinkFacts.rememberedSize(for: .blackCoffee, in: stored)))
        #expect(DrinkFacts.rememberedSize(for: .espresso, in: "not json") > 0)
    }

    @Test("Water: the ml and the day's water including this drink")
    func waterEstimate() {
        let line = DrinkEstimate(volume: 330, contributionPercent: 100, caffeine: 0, alcoholGrams: 0,
                                 waterToday: 1600, waterTarget: 2500, caffeineToday: 64)
        #expect(line.value == "\(VESSFormat.milliliters(330))\u{00A0}ml")
        #expect(line.context.hasPrefix("toward water · "))
        #expect(line.context.contains("→\u{00A0}\(VESSFormat.liters(fromMilliliters: 1930)) of \(VESSFormat.liters(fromMilliliters: 2500))\u{00A0}L with this"))
    }

    @Test("Espresso: ≈ mg, the share toward water and the day's caffeine including it")
    func caffeineEstimate() {
        let line = DrinkEstimate(volume: 30, contributionPercent: 80, caffeine: 63.6, alcoholGrams: 0,
                                 waterToday: 1600, waterTarget: 2500, caffeineToday: 64)
        #expect(line.value == "≈\u{00A0}64\u{00A0}mg")
        #expect(line.context == "caffeine · counts as 24\u{00A0}ml water · →\u{00A0}128 of 400\u{00A0}mg with this")
    }

    @Test("Alcohol doesn't count toward water")
    func alcoholEstimate() {
        let line = DrinkEstimate(volume: 330, contributionPercent: 0, caffeine: 0, alcoholGrams: 13,
                                 waterToday: 0, waterTarget: 2500, caffeineToday: 0)
        #expect(line.context.hasSuffix("doesn't count toward water"))
    }

    @Test("Regular / Half / Decaf: only coffee and tea with caffeine; decaf as the catalog's decaf")
    func strength() {
        #expect(DrinkFacts.offersStrength(.espresso) && DrinkFacts.offersStrength(.tea) && DrinkFacts.offersStrength(.blackCoffee))
        #expect(!DrinkFacts.offersStrength(.water) && !DrinkFacts.offersStrength(.herbalTea) == (DrinkPreset.herbalTea.caffeineMilligramsPer100Milliliters == 0))
        #expect(!DrinkFacts.offersStrength(.decaf) && !DrinkFacts.offersStrength(.milk) && !DrinkFacts.offersStrength(nil))
        #expect(CaffeineStrength.half.factor == 0.5)
        #expect(abs(CaffeineStrength.decaf.factor - 0.025) < 0.0001)
    }

    @Test("Espresso sizes name the shot; More lists every drink not on a tile, once")
    func titlesAndMore() {
        #expect(DrinkFacts.sizeTitle(30, for: .espresso).hasSuffix("· 30\u{00A0}ml"))
        #expect(DrinkFacts.sizeTitle(330, for: .water) == "330\u{00A0}ml")
        let more = DrinkFacts.moreSections.flatMap(\.presets)
        #expect(Set(more).isDisjoint(with: DrinkFacts.sheetPresets))
        #expect(more.count == Set(more).count)
        #expect(more.contains(.smoothie) && more.contains(.wine) && more.contains(.latte))
    }
}
