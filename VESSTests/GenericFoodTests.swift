import Foundation
import Testing
@testable import VESS

@Suite("Generic foods: USDA SR Legacy")
struct GenericFoodTests {
    static let foods: [GenericFood] = (try? GenericFoodDatabase.bundled()) ?? []

    private func food(_ id: String, _ name: String, kcal: Double = 100, portions: [ServingOption] = []) -> GenericFood {
        GenericFood(id: id, name: name, per100g: NutritionFacts(calories: kcal, proteinGrams: 1, carbohydrateGrams: 1, fatGrams: 1), portions: portions)
    }

    @Test("The bundled table has 8,422 foods per 100 g, with unknown values left unknown")
    func bundled() throws {
        #expect(Self.foods.count == 8422)
        let chickpeas = try #require(Self.foods.first { $0.id == "16358" })
        #expect(chickpeas.name == "Chickpeas (garbanzo beans, bengal gram), mature seeds, canned, drained solids")
        #expect(chickpeas.per100g.calories == 139 && chickpeas.per100g.proteinGrams == 7.05)
        #expect(chickpeas.per100g.additional[.saturatedFat] == 0.214)
        #expect(chickpeas.portions == [ServingOption(label: "1 can, drained", amount: 253)])
        let lemon = try #require(Self.foods.first { $0.id == "09523" })
        #expect(lemon.per100g.fiberGrams == nil, "Unknown fibre is not zero")
    }

    @Test("Every USDA ingredient in the Discover recipes is in the table")
    func recipesCovered() throws {
        let ids = Set(Self.foods.map(\.id))
        let missing = try RecipeCatalog.bundled().flatMap(\.ingredients).compactMap { ingredient -> String? in
            if case .usda(let ndb) = ingredient.source, !ids.contains(ndb) { return ndb }
            return nil
        }
        #expect(missing.isEmpty, "\(missing)")
    }

    @Test("Search: every word starts a word of the name; whole words, the food itself, name start, raw or plain, then shorter")
    func ranking() {
        let index = GenericFoodIndex(foods: [
            food("1", "Hummus, commercial"),
            food("2", "Chickpeas, mature seeds, cooked, boiled"),
            food("3", "Chickpeas, mature seeds, raw"),
            food("4", "Chickpea flour"),
            food("5", "Chickpeas, canned"),
            food("6", "Snacks, chickpea crisps"),
            food("7", "Chickpeasoup, dry mix"),
        ])
        #expect(index.search("chickpea", limit: 10).map(\.id) == ["3", "5", "2", "4", "6", "7"])
        // All words must be present; accents and case don't matter.
        #expect(index.search("CHICKPEAS raw", limit: 10).map(\.id) == ["3"])
        #expect(index.search("pois chiche", limit: 10).isEmpty)
        #expect(index.search("hümmus", limit: 10).map(\.id) == ["1"])
        #expect(index.search("  ", limit: 10).isEmpty)
        #expect(index.search("chickpea", limit: 2).count == 2)
    }

    @Test("The food itself before dishes named after it; raw or plain before other forms")
    func headAndRaw() {
        let index = GenericFoodIndex(foods: [
            food("1", "Milk and cereal bar"), food("2", "Milk, whole, 3.25% milkfat"),
            food("3", "Spinach souffle"), food("4", "Spinach, frozen"), food("5", "Spinach, raw"),
            food("6", "Eggplant, raw"), food("7", "Egg, whole, raw, fresh"),
        ])
        #expect(index.search("milk", limit: 5).map(\.id) == ["2", "1"])
        #expect(index.search("spinach", limit: 5).map(\.id) == ["5", "4", "3"])
        #expect(index.search("egg", limit: 5).map(\.id) == ["7", "6"])
    }

    @Test("Real table: the plain food comes first")
    func realSearch() {
        let index = GenericFoodIndex(foods: Self.foods)
        #expect(index.search("spinach", limit: 1).first?.name == "Spinach, raw")
        #expect(index.search("garlic", limit: 1).first?.name == "Garlic, raw")
        #expect(index.search("egg", limit: 3).allSatisfy { $0.name.hasPrefix("Egg,") })
        #expect(index.search("cod", limit: 1).first?.name == "Fish, cod, Atlantic, raw")
        #expect(index.search("chickpea", limit: 1).first?.id == "16056")
    }

    @Test("UK and EU names find the USDA food", arguments: [
        ("courgette", "Squash, zucchini, baby, raw"),
        ("aubergine", "Eggplant, raw"),
        ("coriander", "Coriander (cilantro) leaves, raw"),
        ("rocket", "Arugula, raw"),
        ("prawns", "Crustaceans, shrimp, raw (not previously frozen)"),
        ("spring onions", "Onions, spring or scallions (includes tops and bulb), raw"),
        ("beetroot", "Beets, raw"),
        ("chickpeas", "Chickpeas (garbanzo beans, bengal gram), mature seeds, raw"),
        ("baby spinach", "Spinach, raw"),
        ("bok choy", "Cabbage, chinese (pak-choi), raw"),
        ("jasmine rice", "Rice, white, long-grain, regular, raw, enriched"),
        ("basmati rice", "Rice, white, long-grain, regular, raw, enriched"),
        ("minced beef", "Beef, grass-fed, ground, raw"),
        ("minced turkey", "Ground turkey, raw"),
        ("double cream", "Cream, fluid, heavy whipping"),
        ("single cream", "Cream, fluid, light (coffee cream or table cream)"),
        ("icing sugar", "Sugars, powdered"),
        ("caster sugar", "Sugars, granulated"),
        ("plain flour", "Wheat flour, white, all-purpose, unenriched"),
        ("wholemeal flour", "Wheat flour, whole-grain"),
        ("wholemeal bread", "Bread, whole-wheat, commercially prepared"),
        ("porridge oats", "Oats"),
        ("swede", "Rutabagas, raw"),
        ("mangetout", "Peas, edible-podded, raw"),
        ("sweetcorn", "Corn, sweet, white, raw"),
        ("rapeseed oil", "Oil, canola"),
        ("gherkins", "Pickles, cucumber, sour"),
    ])
    func synonyms(query: String, top: String) {
        #expect(Self.index.search(query, limit: 3).first?.name == top)
    }

    @Test("Quark, tvaroh, skyr and oat drink have no USDA match, so Open Food Facts is used instead")
    func noMatch() {
        for query in ["quark", "tvaroh", "Skyr", "oat drink", "oat drink unsweetened"] {
            #expect(Self.index.search(query, limit: 3).isEmpty, "\(query)")
        }
    }

    @Test("Original words come before their synonyms; other searches are unchanged")
    func originalFirst() {
        let coriander = Self.index.search("coriander", limit: 5).map(\.name)
        #expect(coriander.first == "Coriander (cilantro) leaves, raw")
        #expect(coriander.contains("Spices, coriander seed"))
        #expect(Self.index.search("spinach", limit: 1).first?.name == "Spinach, raw")
        #expect(Self.index.search("courgettes", limit: 1).first?.name == "Squash, zucchini, baby, raw")
    }

    static let index = GenericFoodIndex(foods: foods)

    @Test("Household portions become units after grams; nutrition scales by weight")
    func units() {
        let canned = food("16358", "Chickpeas, canned, drained", kcal: 139, portions: [ServingOption(label: "1 can, drained", amount: 253)])
        #expect(canned.units.map(\.label) == ["gram", "1 can, drained"])
        #expect(canned.units[0].isBaseUnit && canned.units[1].amount == 253)
        #expect(abs(canned.nutrition(grams: 240).calories - 333.6) < 0.001)
    }

    @Test("The database loads once; a pantry item keeps the food the user chose, else the best match")
    @MainActor
    func pantryMatch() async throws {
        let database = GenericFoodDatabase()
        #expect(database.search("spinach").isEmpty)
        await database.load()
        #expect(database.isLoaded && database.food(ndb: "16358") != nil)

        var item = InventoryItem(
            id: UUID(), name: "Chickpeas", quantity: 2, unit: .pack, purchaseDate: nil, expirationDate: nil,
            category: .protein, location: .pantry, notes: nil, status: .available, reminderSnoozedUntil: nil
        )
        #expect(database.food(for: item)?.name.hasPrefix("Chickpea") == true)
        item.genericFoodID = "16358"
        #expect(database.food(for: item)?.id == "16358")

        let store = try LocalStore.inMemory()
        try store.save(item)
        #expect(store.inventory.first?.genericFoodID == "16358")
    }

    @Test("Pantry items from earlier builds have no chosen food")
    func oldPantryItem() throws {
        let old = Data("""
        {"id":"6F1C2E1A-7D0B-4E43-9C55-1B0D7A3C9E13","name":"Rolled oats","quantity":500,"unit":"gram",
        "category":"carbohydrates","location":"pantry","status":"available"}
        """.utf8)
        #expect(try JSONDecoder().decode(InventoryItem.self, from: old).genericFoodID == nil)
    }
}
