import Foundation
import Testing
@testable import VESS

@Suite("Drink sheet")
@MainActor
struct DrinkSheetTests {
    @Test("Size chips per drink and the stepper's step")
    func sizes() {
        #expect(DrinkFacts.sizes(for: .espresso) == [30, 60])
        #expect(DrinkFacts.sizes(for: .blackCoffee) == [150, 250, 350])
        #expect(DrinkFacts.sizes(for: .water) == [250, 330, 500, 750])
        #expect(DrinkFacts.sizes(for: .tea) == DrinkPreset.tea.servings.map(\.milliliters))
        #expect(DrinkFacts.step(for: .espresso) == 10 && DrinkFacts.step(for: .water) == 50)
        #expect(DrinkFacts.sheetPresets.first == .water && DrinkFacts.sheetPresets.count == 8)
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
}
