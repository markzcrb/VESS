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
