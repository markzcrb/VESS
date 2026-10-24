import Foundation
import Testing
@testable import VESS

@Suite("Allergens and nutrition preferences")
struct PreferencesTests {
    /// A profile as an earlier build stored it: five allergens, milk as
    /// "lactose", the old diet fields, no nutrition preferences.
    static func oldProfileJSON(diet: String = "custom", custom: String? = "Pescatarian", other: [String] = [], allergies: [String] = ["lactose", "nuts"]) -> Data {
        let customField = custom.map { "\"customDietDescription\": \"\($0)\"," } ?? ""
        let otherField = other.map { "\"\($0)\"" }.joined(separator: ",")
        let allergyField = allergies.map { "\"\($0)\"" }.joined(separator: ",")
        return Data("""
        {
          "id": "6F1C2E1A-7D0B-4E43-9C55-1B0D7A3C9E11",
          "name": "Mark",
          "dateOfBirth": 0,
          "sex": "male",
          "heightCentimeters": 182,
          "weightKilograms": 78.4,
          "goal": "maintainWeight",
          "activityLevel": "moderate",
          "dietaryPreference": "\(diet)",
          \(customField)
          "allergies": [\(allergyField)],
          "otherRestrictions": [\(otherField)],
          "focusAreas": ["nutrition"],
          "nutritionTargets": { "calories": 2400, "proteinGrams": 120, "carbohydrateGrams": 280, "fatGrams": 75 },
          "waterTargetMilliliters": 2600,
          "createdAt": 0,
          "updatedAt": 0
        }
        """.utf8)
    }

    @Test("A profile from an earlier build decodes; lactose becomes milk")
    func legacyAllergens() throws {
        let profile = try JSONDecoder().decode(UserProfile.self, from: Self.oldProfileJSON())
        #expect(profile.allergies == [.milk, .nuts])
        #expect(Allergen.allCases.count == 14)
    }

    @Test("Allergens round-trip under their new names")
    func roundTrip() throws {
        let all = Set(Allergen.allCases)
        let data = try JSONEncoder().encode(all)
        #expect(try JSONDecoder().decode(Set<Allergen>.self, from: data) == all)
        #expect(!String(decoding: data, as: UTF8.self).contains("lactose"))
    }

    private func migrated(diet: String, custom: String? = nil, other: [String] = [], allergies: [String] = []) throws -> UserProfile {
        let old = try JSONDecoder().decode(UserProfile.self, from: Self.oldProfileJSON(diet: diet, custom: custom, other: other, allergies: allergies))
        #expect(old.nutritionPreferences == nil)
        return UserProfile.migrated(old)
    }

    @Test("Each earlier diet moves to one diet and its preferences")
    func dietMigration() throws {
        let cases: [(String, Diet, Set<FoodPreference>)] = [
            ("everything", .noRestrictions, []),
            ("vegetarian", .vegetarian, []),
            ("vegan", .vegan, []),
            ("highProtein", .noRestrictions, [.highProtein]),
            ("lowCarb", .noRestrictions, [.lowerCarb]),
        ]
        for (old, diet, prefer) in cases {
            let profile = try migrated(diet: old)
            #expect(profile.preferences.diet == diet, "\(old)")
            #expect(profile.preferences.alsoPrefer == prefer, "\(old)")
            #expect(profile.preferences.avoidIngredients.isEmpty)
        }
    }

    @Test("Custom text: a diet name sets the diet; one ingredient is avoided; anything longer is kept")
    func customMigration() throws {
        let pescatarian = try migrated(diet: "custom", custom: "Pescatarian")
        #expect(pescatarian.preferences.diet == .pescatarian)
        #expect(pescatarian.customDietDescription == nil)

        let coriander = try migrated(diet: "custom", custom: "no coriander")
        #expect(coriander.preferences.diet == .noRestrictions)
        #expect(coriander.preferences.avoidIngredients == ["Coriander"])
        #expect(coriander.customDietDescription == nil)

        let long = try migrated(diet: "custom", custom: "Low FODMAP, mostly plants")
        #expect(long.preferences.avoidIngredients.isEmpty)
        #expect(long.customDietDescription == "Low FODMAP, mostly plants")

        let mixed = try migrated(diet: "custom", custom: "Pescatarian, no spicy food")
        #expect(mixed.preferences.diet == .pescatarian)
        #expect(mixed.customDietDescription == "Pescatarian, no spicy food")
    }

    @Test("Other restrictions: single ingredients are avoided, without duplicates; the rest is kept")
    func otherRestrictions() throws {
        let profile = try migrated(diet: "vegetarian", other: ["Mushrooms", "mushrooms ", "blue cheese", "Nothing too spicy please"])
        #expect(profile.preferences.diet == .vegetarian)
        #expect(profile.preferences.avoidIngredients == ["Mushrooms", "Blue cheese"])
        #expect(profile.customDietDescription == "Nothing too spicy please")
        // The earlier fields stay as they were.
        #expect(profile.otherRestrictions.count == 4)
        #expect(profile.dietaryPreference == .vegetarian)
    }

    @Test("Nuts from an earlier build also cover peanuts; a migrated profile is left alone")
    func nutsAndIdempotence() throws {
        let profile = try migrated(diet: "everything", allergies: ["nuts", "lactose"])
        #expect(profile.allergies == [.nuts, .peanuts, .milk])
        var edited = profile
        edited.allergies.remove(.peanuts)
        #expect(UserProfile.migrated(edited) == edited)
    }

    @Test("The store migrates an earlier profile when it opens and keeps it on save")
    @MainActor
    func storeMigrates() throws {
        let store = try LocalStore.inMemory()
        let old = try JSONDecoder().decode(UserProfile.self, from: Self.oldProfileJSON())
        try store.saveProfile(old)
        let saved = try #require(store.profile)
        #expect(saved.nutritionPreferences?.diet == .pescatarian)
        #expect(saved.allergies == [.milk, .nuts, .peanuts])
    }

    @Test("The target calculator keeps getting one diet: high protein wins over lower carb")
    func targetDiet() {
        #expect(NutritionPreferences(alsoPrefer: [.lowerCarb, .highProtein]).targetDiet == .highProtein)
        #expect(NutritionPreferences(alsoPrefer: [.lowerCarb]).targetDiet == .lowCarb)
        #expect(NutritionPreferences(diet: .vegan).targetDiet == .everything)
    }

    @Test("Open Food Facts tags map to the 14 allergens; peanuts are not tree nuts")
    func openFoodFactsTags() throws {
        let product: [String: Any] = [
            "code": "1", "product_name": "Test", "nutriments": ["energy-kcal_100g": 100],
            "allergens_tags": ["en:peanuts", "en:sesame-seeds", "en:crustaceans", "en:molluscs", "en:sulphur-dioxide-and-sulphites", "en:milk"],
        ]
        let food = try #require(OpenFoodFactsMapper.food(from: product, code: nil, retrievedAt: .now))
        #expect(food.allergens == [.peanuts, .sesame, .crustaceans, .molluscs, .sulphites, .milk])
    }
}
