import Foundation
import Testing
@testable import VESS

@MainActor
@Suite("Local store: foods")
struct FoodStoreTests {
    private func customFood(_ name: String, updatedAt: Date = .now) -> Food {
        Food(
            id: UUID(), name: name, brand: nil, barcode: nil, servingSize: 1, servingUnit: .serving,
            nutrition: NutritionFacts(calories: 300, proteinGrams: 20, carbohydrateGrams: 30, fatGrams: 10),
            ingredients: [], allergens: [], quality: nil, source: .userCreated,
            createdAt: updatedAt, updatedAt: updatedAt
        )
    }

    private var banana: Food { StarterCatalog.food(id: StarterCatalog.stableID(for: "banana"))! }

    @Test("Saving a food again updates it and keeps it a favorite")
    func upsertKeepsFavorite() throws {
        let store = try LocalStore.inMemory()
        var food = customFood("Overnight oats")
        try store.save(food)
        try store.setFavorite(true, for: food)

        food.name = "Overnight oats with berries"
        try store.save(food)

        #expect(store.savedFoods().count == 1)
        #expect(store.food(id: food.id)?.name == "Overnight oats with berries")
        #expect(store.favoriteFoodIDs() == [food.id])
        #expect(store.customFoods().map(\.id) == [food.id])
    }

    @Test("A catalog food can be a favorite; un-favoriting removes it from Favorites")
    func catalogFavorite() throws {
        let store = try LocalStore.inMemory()
        try store.setFavorite(true, for: banana)
        #expect(store.favoriteFoods().map(\.name) == ["Banana"])
        #expect(store.customFoods().isEmpty)

        try store.setFavorite(false, for: banana)
        #expect(store.favoriteFoods().isEmpty)
    }

    @Test("Catalog foods are found by ID without being saved")
    func catalogLookup() throws {
        let store = try LocalStore.inMemory()
        #expect(store.food(id: banana.id)?.name == "Banana")
        #expect(store.savedFoods().isEmpty)
    }

    @Test("Recent foods are most recent first, without duplicates or quick adds")
    func recents() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 3, 10, 18)
        let oats = customFood("Oats")
        try store.save(oats)
        let user = UUID()

        try store.add(FoodLogEntry(userID: user, food: banana, quantity: 118, mealType: .breakfast, loggedAt: now.addingTimeInterval(-7200)))
        try store.add(FoodLogEntry(userID: user, food: oats, quantity: 1, mealType: .breakfast, loggedAt: now.addingTimeInterval(-3600)))
        try store.add(FoodLogEntry(userID: user, food: banana, quantity: 118, mealType: .snack, loggedAt: now.addingTimeInterval(-60)))
        try store.add(FoodLogEntry(
            id: UUID(), userID: user, foodID: nil, foodName: "Quick", mealType: .snack, quantity: 1,
            servingUnit: .serving, nutrition: .zero, loggedAt: now.addingTimeInterval(-30)
        ))
        // Too old to be recent.
        try store.add(FoodLogEntry(userID: user, food: customFood("Old"), quantity: 1, mealType: .lunch, loggedAt: now.addingTimeInterval(-90 * 86_400)))

        #expect(store.recentFoods(now: now).map(\.name) == ["Banana", "Oats"])
    }

    @Test("Updating an entry replaces it; a missing entry is an error")
    func updateEntry() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 3, 10, 12)
        let entry = FoodLogEntry(userID: UUID(), food: banana, portion: banana.defaultPortion, mealType: .breakfast, loggedAt: now)
        try store.add(entry)

        try store.update(entry.updated(portionCount: 2, mealType: .snack))

        let saved = try #require(store.foodEntries(on: now, calendar: TestClock.utc).first)
        #expect(saved.mealType == .snack)
        #expect(saved.quantity == 236)
        #expect(saved.nutrition.calories.isApproximately(entry.nutrition.calories * 2))
        #expect(store.foodEntries(on: now, calendar: TestClock.utc).count == 1)

        let unknown = FoodLogEntry(userID: UUID(), food: banana, quantity: 1, mealType: .lunch, loggedAt: now)
        #expect(throws: LocalStore.LocalStoreError.notFound) { try store.update(unknown) }
    }

    @Test("Logged entries keep their snapshot when the food changes")
    func snapshotsSurviveDeletion() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 3, 10, 12)
        let food = customFood("Soup")
        try store.save(food)
        try store.add(FoodLogEntry(userID: UUID(), food: food, quantity: 2, mealType: .dinner, loggedAt: now))

        var changed = food
        changed.nutrition.calories = 1
        try store.save(changed)

        let entry = try #require(store.foodEntries(on: now, calendar: TestClock.utc).first)
        #expect(entry.foodName == "Soup")
        #expect(entry.nutrition.calories == 600)
    }

    @Test("Local search covers saved foods and the catalog, without the network")
    func localSearch() throws {
        let store = try LocalStore.inMemory()
        try store.save(customFood("Banana bread"))
        #expect(store.searchLocalFoods("banana").map(\.name) == ["Banana", "Banana bread"])
        #expect(store.searchLocalFoods("").isEmpty)
    }

    @Test("Deleting all data removes saved foods too")
    func deleteAll() throws {
        let store = try LocalStore.inMemory()
        try store.save(customFood("Mine"))
        try store.setFavorite(true, for: banana)
        try store.deleteAllData()
        #expect(store.savedFoods().isEmpty)
        #expect(store.favoriteFoodIDs().isEmpty)
    }
}
