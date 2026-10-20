import Foundation
import Testing
@testable import VESS

@Suite("Starter catalog")
struct StarterCatalogTests {
    @Test("Catalog IDs are unique and the same on every launch")
    func stableIDs() {
        let ids = StarterCatalog.foods.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(StarterCatalog.stableID(for: "banana") == StarterCatalog.stableID(for: "banana"))
        #expect(StarterCatalog.food(id: StarterCatalog.stableID(for: "banana"))?.name == "Banana")
        #expect(UUID(stableKey: "a") != UUID(stableKey: "b"))
    }

    @Test("Catalog energy roughly matches its macros (4/4/9 kcal per gram)")
    func energyConsistency() {
        for food in StarterCatalog.foods {
            let n = food.nutrition
            let estimate = 4 * n.proteinGrams + 4 * n.carbohydrateGrams + 9 * n.fatGrams
            // Fiber and Atwater factors make exact agreement impossible; catch typos only.
            #expect(abs(estimate - n.calories) <= max(15, n.calories * 0.15), "\(food.name): \(n.calories) kcal vs \(estimate)")
        }
    }

    @Test("Every catalog food is complete, sourced and loggable")
    func completeness() {
        for food in StarterCatalog.foods {
            #expect(food.source == .starterCatalog)
            #expect(food.nutrition.canBeLogged)
            #expect(food.nutrition.unreportedCoreNutrients == nil)
            #expect(food.servingSize == 100)
            #expect(food.sourceInfo?.isCommunityContributed == false)
            #expect(!(food.servingOptions ?? []).isEmpty, "\(food.name) has no portion")
        }
    }
}

@Suite("Food search")
struct FoodSearchTests {
    private func food(_ name: String, brand: String? = nil) -> Food {
        Food(
            id: UUID(stableKey: "test.\(name).\(brand ?? "")"), name: name, brand: brand, barcode: nil,
            servingSize: 100, servingUnit: .gram, nutrition: .zero, ingredients: [], allergens: [],
            quality: nil, source: .userCreated, createdAt: .distantPast, updatedAt: .distantPast
        )
    }

    @Test("Matching ignores case and accents")
    func accentFolding() {
        let foods = [food("Crème fraîche"), food("Jalapeño")]
        #expect(FoodSearch.results(for: "creme", in: foods).map(\.name) == ["Crème fraîche"])
        #expect(FoodSearch.results(for: "JALAPENO", in: foods).map(\.name) == ["Jalapeño"])
    }

    @Test("Every word must match, in name or brand")
    func allTerms() {
        let foods = [food("Greek yogurt", brand: "Fage"), food("Greek salad")]
        #expect(FoodSearch.results(for: "greek fage", in: foods).map(\.name) == ["Greek yogurt"])
        #expect(FoodSearch.results(for: "greek", in: foods).count == 2)
        #expect(FoodSearch.results(for: "   ", in: foods).isEmpty)
    }

    @Test("Name prefix beats word prefix beats substring; favorites rank up")
    func ranking() {
        let rice = food("Rice cakes")
        let brown = food("Brown rice")
        let licorice = food("Licorice")
        #expect(FoodSearch.results(for: "rice", in: [licorice, brown, rice]).map(\.name) == ["Rice cakes", "Brown rice", "Licorice"])
        // A favorite gets +20: enough to beat a substring match, not a prefix.
        #expect(FoodSearch.results(for: "rice", in: [rice, brown, licorice], favorites: [licorice.id]).map(\.name) == ["Rice cakes", "Brown rice", "Licorice"])
        let other = food("Brown rice cakes")
        #expect(FoodSearch.results(for: "rice", in: [brown, other], favorites: [other.id]).map(\.name) == ["Brown rice cakes", "Brown rice"])
    }

    @Test("Duplicate IDs appear once")
    func deduplicates() {
        let apple = food("Apple")
        #expect(FoodSearch.results(for: "apple", in: [apple, apple]).count == 1)
    }

    @Test("Catalog search finds common foods")
    func catalog() {
        #expect(FoodSearch.results(for: "lentil", in: StarterCatalog.foods).first?.name == "Lentils, cooked")
    }
}

@MainActor
@Suite("Portions and entries")
struct PortionTests {
    private var bread: Food { StarterCatalog.food(id: StarterCatalog.stableID(for: "bread.wholewheat"))! }

    @Test("Portion options list named portions, then the base unit")
    func options() {
        #expect(bread.portionOptions.map(\.label) == ["1 slice", "gram"])
        #expect(bread.defaultPortion == Portion(option: ServingOption(label: "1 slice", amount: 32), count: 1))
    }

    @Test("Logging 2 slices snapshots nutrition for 64 g")
    func portionEntry() {
        let portion = Portion(option: ServingOption(label: "1 slice", amount: 32), count: 2)
        let entry = FoodLogEntry(userID: UUID(), food: bread, portion: portion, mealType: .breakfast, loggedAt: .now)

        #expect(entry.quantity == 64)
        #expect(entry.portionLabel == "1 slice")
        #expect(entry.portionAmount == 32)
        #expect(entry.portionCount == 2)
        #expect(entry.source == .starterCatalog)
        #expect(entry.nutrition.calories.isApproximately(252 * 0.64))
    }

    @Test("Logging in grams stores no portion label")
    func baseUnitEntry() {
        let entry = FoodLogEntry(userID: UUID(), food: bread, portion: Portion(option: .baseUnit(.gram), count: 50), mealType: .lunch, loggedAt: .now)
        #expect(entry.quantity == 50)
        #expect(entry.portionLabel == nil)
        #expect(entry.portionCount == 50)
    }

    @Test("Editing rescales the snapshot, not the current food")
    func editing() {
        var food = bread
        let entry = FoodLogEntry(userID: UUID(), food: food, portion: food.defaultPortion, mealType: .breakfast, loggedAt: .now)
        food.nutrition.calories = 9999 // The food changes later; history must not.

        let edited = entry.updated(portionCount: 3, mealType: .snack)
        #expect(edited.mealType == .snack)
        #expect(edited.quantity == 96)
        #expect(edited.nutrition.calories.isApproximately(entry.nutrition.calories * 3))
        #expect(edited.id == entry.id)

        let grams = FoodLogEntry(userID: UUID(), food: bread, quantity: 50, mealType: .lunch, loggedAt: .now)
        #expect(grams.updated(portionCount: 100, mealType: .lunch).nutrition.calories.isApproximately(252))
    }

    @Test("Portion text reads naturally")
    func portionText() {
        let slice = ServingOption(label: "1 slice", amount: 32)
        #expect(Portion(option: slice, count: 1).text(unit: .gram) == "1 slice (32 g)")
        // Decimal separator follows the device locale.
        #expect(Portion(option: slice, count: 1.5).text(unit: .gram) == "\(VESSFormat.quantity(1.5)) × 1 slice (48 g)")
        #expect(Portion(option: .baseUnit(.milliliter), count: 250).text(unit: .milliliter) == "250 ml")
    }
}

@Suite("Unreported nutrients")
struct UnreportedNutrientTests {
    @Test("Totals remember which nutrients some foods didn't report")
    func totalsUnion() {
        let complete = NutritionFacts(calories: 100, proteinGrams: 5, carbohydrateGrams: 10, fatGrams: 2)
        var noProtein = NutritionFacts(calories: 50, proteinGrams: 0, carbohydrateGrams: 5, fatGrams: 1)
        noProtein.unreportedCoreNutrients = [.protein]

        let total = [complete, noProtein].total
        #expect(total.calories == 150)
        #expect(total.proteinGrams == 5)
        #expect(total.unreportedCoreNutrients == [.protein])
        #expect([complete, complete].total.unreportedCoreNutrients == nil)
        #expect(!total.isReported(.protein))
        #expect(total.isReported(.fat))
    }

    @Test("Scaling keeps unreported nutrients unreported")
    func scaling() {
        var facts = NutritionFacts(calories: 100, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
        facts.unreportedCoreNutrients = [.carbohydrates]
        #expect(facts.scaled(by: 2).unreportedCoreNutrients == [.carbohydrates])
    }

    @Test("Food without calories can't be logged")
    func caloriesRequired() {
        var facts = NutritionFacts.zero
        #expect(facts.canBeLogged)
        facts.unreportedCoreNutrients = [.calories]
        #expect(!facts.canBeLogged)
    }

    @MainActor
    @Test("An empty field is unreported, not zero; invalid input is rejected")
    func nutrientInput() {
        #expect(NutrientInput.grams("") == .some(nil))
        #expect(NutrientInput.grams("12") == .some(12))
        #expect(NutrientInput.grams("abc") == nil)
        #expect(NutrientInput.grams("5000") == nil)

        let facts = NutrientInput.facts(calories: 300, protein: 20, carbs: nil, fat: nil)
        #expect(facts.unreportedCoreNutrients == [.carbohydrates, .fat])
        #expect(NutrientInput.facts(calories: 300, protein: 1, carbs: 2, fat: 3).unreportedCoreNutrients == nil)
    }
}
