import Foundation
import Testing
@testable import VESS

@Suite("Menu scan: fit, ranking and logging")
struct MenuScanTests {
    /// M02's menu, as the server would send it.
    private static let json = #"""
    {"title":"The evening menu","note":"","remaining":9,"dishes":[
    {"name":"Roasted beet salad","section":"Appetizer","menu_text":"Roasted Beet Salad (V) · 16","portion_g":250,"kcal":360,"protein_g":10,"carbs_g":26,"fat_g":24,"ingredients":["Beetroot","goat cheese","rocket"],"allergens":["milk"],"contains":["dairy"],"confidence":"medium"},
    {"name":"Heirloom tomato bruschetta","section":"Appetizer","menu_text":"","portion_g":180,"kcal":320,"protein_g":9,"carbs_g":40,"fat_g":14,"ingredients":["Sourdough bread","tomatoes"],"allergens":["gluten"],"contains":[],"confidence":"medium"},
    {"name":"Beef carpaccio with arugula","section":"Appetizer","portion_g":150,"kcal":290,"protein_g":24,"carbs_g":3,"fat_g":20,"ingredients":["Beef tenderloin","parmesan"],"allergens":["milk"],"contains":["meat","dairy"],"confidence":"medium"},
    {"name":"Moules marinières","section":"Appetizer","portion_g":400,"kcal":480,"protein_g":36,"carbs_g":24,"fat_g":22,"ingredients":["Mussels","white wine","butter"],"allergens":["molluscs","milk"],"contains":["molluscs","dairy","alcohol"],"confidence":"medium"},
    {"name":"Wild mushroom soup","section":"Appetizer","portion_g":300,"kcal":260,"protein_g":6,"carbs_g":18,"fat_g":18,"ingredients":["Cream","onion"],"allergens":["milk"],"contains":["dairy"],"confidence":"medium"},
    {"name":"Pan-seared duck breast","section":"Main course","portion_g":350,"kcal":720,"protein_g":44,"carbs_g":30,"fat_g":46,"ingredients":["Duck breast","cherries"],"allergens":[],"contains":["poultry","alcohol"],"confidence":"medium"},
    {"name":"Grilled ribeye with herb butter","section":"Main course","portion_g":400,"kcal":880,"protein_g":58,"carbs_g":20,"fat_g":64,"ingredients":["Ribeye steak","herb butter"],"allergens":["milk"],"contains":["meat","dairy"],"confidence":"medium"},
    {"name":"Wild mushroom risotto","section":"Main course","portion_g":380,"kcal":640,"protein_g":14,"carbs_g":78,"fat_g":28,"ingredients":["Arborio rice","mixed mushrooms","parmesan"],"allergens":["milk"],"contains":["dairy"],"confidence":"medium"},
    {"name":"Salmon fillet with asparagus and lemon","section":"Main course","portion_g":380,"kcal":560,"protein_g":42,"carbs_g":14,"fat_g":34,"ingredients":["Salmon","asparagus","butter"],"allergens":["fish","milk"],"contains":["fish","dairy"],"confidence":"medium"},
    {"name":"Rack of lamb with mint sauce","section":"Main course","portion_g":400,"kcal":820,"protein_g":52,"carbs_g":22,"fat_g":56,"ingredients":["Lamb","potatoes"],"allergens":[],"contains":["meat"],"confidence":"low"}
    ]}
    """#

    private let mark = NutritionPreferences(diet: .pescatarian, alsoPrefer: [.highProtein], avoidIngredients: ["Coriander", "Mushrooms", "Blue cheese"])
    private let nutFree: Set<Allergen> = [.nuts, .peanuts]

    private func rows() throws -> [MenuRules.Row] {
        let response = try JSONDecoder().decode(MenuScanResponse.self, from: Data(Self.json.utf8))
        return MenuRules.rows(MenuRules.dishes(from: response), preferences: mark, allergies: nutFree)
    }

    private func row(_ name: String, in rows: [MenuRules.Row]) -> MenuRules.Row? {
        rows.first { $0.dish.name.hasPrefix(name) }
    }

    @Test("The reply decodes: EU-14 allergens and contents map; an empty menu line is dropped")
    func decode() throws {
        let rows = try rows()
        #expect(rows.count == 10)
        let salmon = try #require(row("Salmon", in: rows))
        #expect(salmon.dish.allergens == [.fish, .milk])
        #expect(salmon.dish.contains == [.fish, .dairy])
        #expect(row("Heirloom", in: rows)?.dish.menuText == nil)
        #expect(row("Rack", in: rows)?.dish.confidence == .low)
    }

    @Test("Pescatarian, avoiding mushrooms: meat, poultry and mushrooms (in the name too) don't fit; six of ten")
    func fit() throws {
        let rows = try rows()
        let notFitting = rows.filter { !$0.fit.fits }.map(\.dish.name)
        #expect(notFitting.count == 6)
        #expect(row("Pan-seared duck", in: rows)?.fit.fits == false)
        #expect(row("Wild mushroom soup", in: rows)?.fit.reasons.contains(.avoid("Mushrooms")) == true, "Matched on the dish name")
        #expect(row("Moules", in: rows)?.fit.fits == true)
    }

    @Test("A confirmed allergen doesn't fit; a dish that often has one is \"Ask\"")
    func allergens() throws {
        let rows = try rows()
        let beet = try #require(row("Roasted beet", in: rows))
        #expect(beet.fit.fits)
        #expect(beet.fit.hints == [MenuHint(allergen: .nuts, word: "walnuts")])
        let milkFree = MenuRules.fit(beet.dish, preferences: mark, allergies: [.milk])
        #expect(!milkFree.fits && milkFree.allergens == [.milk])
        #expect(MenuRules.hints(for: beet.dish, allergies: []).isEmpty, "No hint without the allergy")
    }

    @Test("Best for you: fits only, closest to the protein left, within the energy left first; low confidence last")
    func ranking() throws {
        let rows = try rows()
        let best = MenuRules.list(rows, filter: .best, caloriesLeft: 1120, proteinLeft: 58).map(\.dish.name)
        #expect(best == ["Salmon fillet with asparagus and lemon", "Moules marinières", "Roasted beet salad", "Heirloom tomato bruschetta"])
        #expect(MenuRules.bestProtein(rows, caloriesLeft: 1120) == row("Salmon", in: rows)?.id)
        // Above the energy left goes after the dishes within it.
        let tight = MenuRules.list(rows, filter: .best, caloriesLeft: 500, proteinLeft: 58).map(\.dish.name)
        #expect(tight.last == "Salmon fillet with asparagus and lemon")
    }

    @Test("High-protein and Lighter chips; All is every dish in menu order")
    func chips() throws {
        let rows = try rows()
        #expect(MenuRules.list(rows, filter: .highProtein, caloriesLeft: 1120, proteinLeft: 58).map(\.dish.name)
                == ["Salmon fillet with asparagus and lemon", "Moules marinières"])
        #expect(MenuRules.list(rows, filter: .lighter, caloriesLeft: 1120, proteinLeft: 58).map(\.dish.name)
                == ["Heirloom tomato bruschetta", "Roasted beet salad", "Moules marinières"])
        #expect(MenuRules.list(rows, filter: .all, caloriesLeft: 1120, proteinLeft: 58).map(\.id) == Array(0..<10))
    }

    @Test("Logged as photo estimates with the menu name; Larger is ×1.25")
    func entries() throws {
        let rows = try rows()
        let salmon = try #require(row("Salmon", in: rows)).dish
        let moules = try #require(row("Moules", in: rows)).dish
        let entries = MenuRules.entries([(salmon, .regular), (moules, .larger)], menuName: "The evening menu",
                                        userID: UUID(), meal: .dinner, at: Date(timeIntervalSince1970: 0))
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.source == .photoEstimate && $0.menuName == "The evening menu" && $0.mealType == .dinner })
        #expect(entries[1].nutrition.calories == 600 && entries[1].quantity == 500)
        #expect(entries.map(\.nutrition.calories).reduce(0, +) == 1160)
    }
}
