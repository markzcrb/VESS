import Foundation

/// A small built-in catalog of common generic foods, so search works on the
/// first launch and fully offline. Deliberately small; branded products come
/// from Open Food Facts and the user's own foods.
///
/// Values are typical figures per 100 g (or 100 ml), rounded from USDA
/// FoodData Central (public domain). Sodium is left unreported rather than
/// guessed. IDs are derived from a stable key, so favorites and recent foods
/// keep working across app updates.
nonisolated enum StarterCatalog {
    static let provider = "USDA FoodData Central (typical values)"

    static let foods: [Food] = entries.map(\.food)

    static func food(id: UUID) -> Food? {
        byID[id]
    }

    private static let byID: [UUID: Food] = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })

    /// The stable ID of the catalog entry with `key`.
    static func stableID(for key: String) -> UUID {
        UUID(stableKey: "vess.catalog.\(key)")
    }

    private struct Entry {
        let key: String
        let name: String
        let unit: QuantityUnit
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double?
        let sugar: Double?
        let portions: [(String, Double)]
        var allergens: Set<Allergen> = []

        var food: Food {
            // A fixed date: catalog items are not "created" on the device.
            let reference = Date(timeIntervalSince1970: 1_790_000_000)
            return Food(
                id: StarterCatalog.stableID(for: key),
                name: name,
                brand: nil,
                barcode: nil,
                servingSize: 100,
                servingUnit: unit,
                nutrition: NutritionFacts(
                    calories: kcal,
                    proteinGrams: protein,
                    carbohydrateGrams: carbs,
                    fatGrams: fat,
                    fiberGrams: fiber,
                    sugarGrams: sugar
                ),
                ingredients: [],
                allergens: allergens,
                quality: nil,
                source: .starterCatalog,
                createdAt: reference,
                updatedAt: reference,
                servingOptions: portions.map { ServingOption(label: $0.0, amount: $0.1) },
                sourceInfo: FoodSourceInfo(
                    provider: StarterCatalog.provider,
                    externalID: nil,
                    retrievedAt: nil,
                    url: nil,
                    license: "Public domain",
                    isCommunityContributed: false
                )
            )
        }
    }

    // kcal, protein, carbs, fat, fiber, sugar per 100 g / 100 ml.
    private static let entries: [Entry] = [
        // Fruit
        Entry(key: "apple", name: "Apple", unit: .gram, kcal: 52, protein: 0.3, carbs: 13.8, fat: 0.2, fiber: 2.4, sugar: 10.4, portions: [("1 medium", 182)]),
        Entry(key: "banana", name: "Banana", unit: .gram, kcal: 89, protein: 1.1, carbs: 22.8, fat: 0.3, fiber: 2.6, sugar: 12.2, portions: [("1 medium", 118)]),
        Entry(key: "orange", name: "Orange", unit: .gram, kcal: 47, protein: 0.9, carbs: 11.8, fat: 0.1, fiber: 2.4, sugar: 9.4, portions: [("1 medium", 131)]),
        Entry(key: "strawberries", name: "Strawberries", unit: .gram, kcal: 32, protein: 0.7, carbs: 7.7, fat: 0.3, fiber: 2.0, sugar: 4.9, portions: [("1 cup", 152)]),
        Entry(key: "blueberries", name: "Blueberries", unit: .gram, kcal: 57, protein: 0.7, carbs: 14.5, fat: 0.3, fiber: 2.4, sugar: 10.0, portions: [("1 cup", 148)]),
        Entry(key: "avocado", name: "Avocado", unit: .gram, kcal: 160, protein: 2.0, carbs: 8.5, fat: 14.7, fiber: 6.7, sugar: 0.7, portions: [("½ avocado", 75)]),
        // Vegetables
        Entry(key: "broccoli", name: "Broccoli", unit: .gram, kcal: 34, protein: 2.8, carbs: 6.6, fat: 0.4, fiber: 2.6, sugar: 1.7, portions: [("1 cup, chopped", 91)]),
        Entry(key: "carrot", name: "Carrot", unit: .gram, kcal: 41, protein: 0.9, carbs: 9.6, fat: 0.2, fiber: 2.8, sugar: 4.7, portions: [("1 medium", 61)]),
        Entry(key: "spinach", name: "Spinach", unit: .gram, kcal: 23, protein: 2.9, carbs: 3.6, fat: 0.4, fiber: 2.2, sugar: 0.4, portions: [("1 cup", 30)]),
        Entry(key: "tomato", name: "Tomato", unit: .gram, kcal: 18, protein: 0.9, carbs: 3.9, fat: 0.2, fiber: 1.2, sugar: 2.6, portions: [("1 medium", 123)]),
        Entry(key: "cucumber", name: "Cucumber", unit: .gram, kcal: 15, protein: 0.7, carbs: 3.6, fat: 0.1, fiber: 0.5, sugar: 1.7, portions: [("½ cucumber", 150)]),
        Entry(key: "potato.boiled", name: "Potato, boiled", unit: .gram, kcal: 87, protein: 1.9, carbs: 20.1, fat: 0.1, fiber: 1.8, sugar: 0.9, portions: [("1 medium", 170)]),
        Entry(key: "sweet-potato.baked", name: "Sweet potato, baked", unit: .gram, kcal: 90, protein: 2.0, carbs: 20.7, fat: 0.2, fiber: 3.3, sugar: 6.5, portions: [("1 medium", 114)]),
        // Grains
        Entry(key: "rice.white.cooked", name: "White rice, cooked", unit: .gram, kcal: 130, protein: 2.7, carbs: 28.2, fat: 0.3, fiber: 0.4, sugar: 0.1, portions: [("1 cup", 158)]),
        Entry(key: "rice.brown.cooked", name: "Brown rice, cooked", unit: .gram, kcal: 123, protein: 2.7, carbs: 25.6, fat: 1.0, fiber: 1.6, sugar: 0.2, portions: [("1 cup", 195)]),
        Entry(key: "pasta.cooked", name: "Pasta, cooked", unit: .gram, kcal: 158, protein: 5.8, carbs: 30.9, fat: 0.9, fiber: 1.8, sugar: 0.6, portions: [("1 cup", 140)], allergens: [.gluten]),
        Entry(key: "oats.rolled", name: "Rolled oats", unit: .gram, kcal: 379, protein: 13.2, carbs: 67.7, fat: 6.5, fiber: 10.1, sugar: 1.0, portions: [("½ cup", 40)], allergens: [.gluten]),
        Entry(key: "bread.wholewheat", name: "Whole wheat bread", unit: .gram, kcal: 252, protein: 12.4, carbs: 42.7, fat: 3.5, fiber: 6.0, sugar: 4.4, portions: [("1 slice", 32)], allergens: [.gluten]),
        // Protein
        Entry(key: "chicken-breast.cooked", name: "Chicken breast, cooked", unit: .gram, kcal: 165, protein: 31.0, carbs: 0, fat: 3.6, fiber: 0, sugar: 0, portions: [("1 fillet", 120)]),
        Entry(key: "salmon.cooked", name: "Salmon, cooked", unit: .gram, kcal: 206, protein: 22.1, carbs: 0, fat: 12.4, fiber: 0, sugar: 0, portions: [("1 fillet", 150)]),
        Entry(key: "tuna.canned-water", name: "Tuna, canned in water", unit: .gram, kcal: 116, protein: 25.5, carbs: 0, fat: 0.8, fiber: 0, sugar: 0, portions: [("1 can, drained", 120)]),
        Entry(key: "egg.boiled", name: "Egg, boiled", unit: .gram, kcal: 155, protein: 12.6, carbs: 1.1, fat: 10.6, fiber: 0, sugar: 1.1, portions: [("1 large", 50)], allergens: [.eggs]),
        Entry(key: "beef.ground-85.cooked", name: "Ground beef 85% lean, cooked", unit: .gram, kcal: 250, protein: 25.9, carbs: 0, fat: 15.4, fiber: 0, sugar: 0, portions: [("1 patty", 85)]),
        Entry(key: "tofu.firm", name: "Tofu, firm", unit: .gram, kcal: 144, protein: 17.3, carbs: 2.8, fat: 8.7, fiber: 2.3, sugar: 0.6, portions: [("½ block", 170)], allergens: [.soy]),
        Entry(key: "lentils.cooked", name: "Lentils, cooked", unit: .gram, kcal: 116, protein: 9.0, carbs: 20.1, fat: 0.4, fiber: 7.9, sugar: 1.8, portions: [("1 cup", 198)]),
        Entry(key: "chickpeas.cooked", name: "Chickpeas, cooked", unit: .gram, kcal: 164, protein: 8.9, carbs: 27.4, fat: 2.6, fiber: 7.6, sugar: 4.8, portions: [("1 cup", 164)]),
        // Dairy
        Entry(key: "yogurt.greek-2", name: "Greek yogurt 2%, plain", unit: .gram, kcal: 73, protein: 9.9, carbs: 3.9, fat: 2.0, fiber: 0, sugar: 3.6, portions: [("1 pot", 170)], allergens: [.milk]),
        Entry(key: "milk.2", name: "Milk 2%", unit: .milliliter, kcal: 50, protein: 3.3, carbs: 4.8, fat: 2.0, fiber: 0, sugar: 5.1, portions: [("1 glass", 250)], allergens: [.milk]),
        Entry(key: "cheddar", name: "Cheddar cheese", unit: .gram, kcal: 403, protein: 24.9, carbs: 1.3, fat: 33.1, fiber: 0, sugar: 0.5, portions: [("1 slice", 28)], allergens: [.milk]),
        // Nuts, fats and extras
        Entry(key: "almonds", name: "Almonds", unit: .gram, kcal: 579, protein: 21.2, carbs: 21.6, fat: 49.9, fiber: 12.5, sugar: 4.4, portions: [("1 handful", 28)], allergens: [.nuts]),
        Entry(key: "peanut-butter", name: "Peanut butter", unit: .gram, kcal: 588, protein: 25.1, carbs: 20.0, fat: 50.4, fiber: 6.0, sugar: 9.2, portions: [("1 tbsp", 16)], allergens: [.nuts]),
        Entry(key: "olive-oil", name: "Olive oil", unit: .gram, kcal: 884, protein: 0, carbs: 0, fat: 100, fiber: 0, sugar: 0, portions: [("1 tbsp", 13.5)]),
        Entry(key: "butter", name: "Butter", unit: .gram, kcal: 717, protein: 0.9, carbs: 0.1, fat: 81.1, fiber: 0, sugar: 0.1, portions: [("1 tbsp", 14)], allergens: [.milk]),
        Entry(key: "honey", name: "Honey", unit: .gram, kcal: 304, protein: 0.3, carbs: 82.4, fat: 0, fiber: 0.2, sugar: 82.1, portions: [("1 tbsp", 21)]),
        Entry(key: "dark-chocolate", name: "Dark chocolate 70–85%", unit: .gram, kcal: 598, protein: 7.8, carbs: 45.9, fat: 42.6, fiber: 10.9, sugar: 24.0, portions: [("1 square", 10)]),
    ]
}
