import Foundation
import Testing
@testable import VESS

@Suite("Grocery list")
struct GroceryListTests {
    private let calendar = TestClock.utc

    private func meal(_ name: String, on day: Date, items: [(String, Double?, QuantityUnit?)]) -> PlannedMeal {
        PlannedMeal(
            id: UUID(), day: calendar.startOfDay(for: day), mealType: .dinner, name: name,
            nutrition: NutritionFacts(calories: 600, proteinGrams: 30, carbohydrateGrams: 60, fatGrams: 20),
            items: items.map { PlannedMeal.Item(name: $0.0, quantity: $0.1, unit: $0.2) },
            source: .foods, loggedAt: nil, createdAt: day
        )
    }

    private func pantry(_ name: String) -> InventoryItem {
        InventoryItem(id: UUID(), name: name, quantity: 1, unit: .piece, purchaseDate: nil, expirationDate: nil,
                      category: .other, location: .pantry, notes: nil, status: .available, reminderSnoozedUntil: nil)
    }

    private func state(_ name: String, checked: Bool = false, manual: Bool = false, dismissed: Bool = false, at date: Date) -> GroceryItem {
        GroceryItem(id: UUID(), key: GroceryList.key(for: name), name: name, quantity: manual ? 1 : nil, unit: manual ? .liter : nil,
                    aisle: nil, isChecked: checked, isManual: manual, isDismissed: dismissed, createdAt: date)
    }

    @Test("Built from meals planned today through the week's end, minus the pantry; amounts add up")
    func build() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let end = try TestClock.date(2026, 10, 12, 0)
        let planned = [
            meal("Pasta", on: try TestClock.date(2026, 10, 7), items: [("Cherry tomatoes", 200, .gram), ("Pasta", 250, .gram)]),
            meal("Bowl", on: try TestClock.date(2026, 10, 8), items: [("Cherry tomatoes", 150, .gram), ("Rice", 90, .gram)]),
            meal("Yesterday", on: try TestClock.date(2026, 10, 5), items: [("Leeks", 1, .piece)]),
            meal("Next week", on: try TestClock.date(2026, 10, 13), items: [("Kale", 1, .piece)]),
        ]
        let list = GroceryList(planned: planned, pantry: [pantry("Jasmine rice")], states: [], from: now, to: end, calendar: calendar)

        #expect(list.plannedMealCount == 2)
        #expect(list.leftOffCount == 1, "Rice is at home")
        let tomatoes = try #require(list.lines.first { $0.name == "Cherry tomatoes" })
        #expect(tomatoes.quantity == 350)
        #expect(tomatoes.meals.count == 2)
        #expect(tomatoes.aisle == .produce)
        #expect(list.lines.map(\.name) == ["Cherry tomatoes", "Pasta"], "Produce before pantry staples")
    }

    @Test("Checked lines sort last; dismissed lines leave; manual items join; last week's choices expire")
    func states() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let end = try TestClock.date(2026, 10, 12, 0)
        let planned = [meal("Tacos", on: try TestClock.date(2026, 10, 9), items: [("Limes", 2, .piece), ("White fish", 300, .gram), ("Basil", nil, nil)])]
        let states = [
            state("Limes", checked: true, at: now),
            state("Basil", dismissed: true, at: now),
            state("White fish", dismissed: true, at: try TestClock.date(2026, 9, 30)),
            state("Oat milk", manual: true, at: try TestClock.date(2026, 9, 30)),
        ]
        let list = GroceryList(planned: planned, pantry: [], states: states, from: now, to: end, calendar: calendar)

        #expect(list.lines.map(\.name) == ["White fish", "Oat milk", "Limes"])
        #expect(list.checked.map(\.name) == ["Limes"])
        #expect(list.lines.first { $0.name == "Oat milk" }?.isManual == true)
    }

    @Test("Done shopping turns checked lines into pantry items, fresh ones in the fridge, without a use-by date")
    func doneShopping() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let end = try TestClock.date(2026, 10, 12, 0)
        let planned = [meal("Tacos", on: try TestClock.date(2026, 10, 9), items: [("Limes", 2, .piece), ("Pasta", 250, .gram)])]
        let list = GroceryList(planned: planned, pantry: [], states: [state("Limes", checked: true, at: now), state("Pasta", checked: true, at: now)], from: now, to: end, calendar: calendar)
        let items = list.pantryItems(now: now)
        #expect(items.map(\.name) == ["Limes", "Pasta"])
        #expect(items.map(\.location) == [.fridge, .pantry])
        #expect(items.allSatisfy { $0.expirationDate == nil })
        #expect(items.first?.quantity == 2)
    }

    @Test("Aisles are guessed from a fixed word list, else Other")
    func aisles() {
        #expect(GroceryAisle.guess(for: "Salmon fillet") == .fish)
        #expect(GroceryAisle.guess(for: "Oat milk") == .dairyEggs)
        #expect(GroceryAisle.guess(for: "Rye bread") == .bakery)
        #expect(GroceryAisle.guess(for: "White beans") == .pantryStaples)
        #expect(GroceryAisle.guess(for: "Red cabbage") == .produce)
        #expect(GroceryAisle.guess(for: "Coffee beans") == .pantryStaples)
        #expect(GroceryAisle.guess(for: "Dish soap") == .other)
    }
}
