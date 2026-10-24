import Foundation

/// Turns an Open Food Facts product object into a VESS `Food`.
///
/// Rules:
/// - Values are per 100 g / 100 ml (`*_100g` keys), the basis OFF normalizes to.
/// - A missing core value is marked unreported, never filled with 0.
/// - Optional nutrients stay `nil` when absent.
/// - Numbers may arrive as JSON numbers or strings; both are accepted.
nonisolated enum OpenFoodFactsMapper {
    static let productPageBase = "https://world.openfoodfacts.org/product/"

    static func food(from product: [String: Any], code fallbackCode: String?, retrievedAt: Date) -> Food? {
        guard let code = (string(product["code"]) ?? fallbackCode)?.filter(\.isNumber), !code.isEmpty,
              let name = firstNonEmpty(product["product_name"], product["product_name_en"], product["generic_name"])
        else {
            return nil
        }
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Double? {
            number(nutriments[key]).flatMap { $0 >= 0 ? $0 : nil }
        }

        let calories = value("energy-kcal_100g")
            ?? (value("energy-kj_100g") ?? value("energy_100g")).map { $0 / 4.184 }
        let protein = value("proteins_100g")
        let carbs = value("carbohydrates_100g")
        let fat = value("fat_100g")

        var unreported = Set<CoreNutrient>()
        if calories == nil { unreported.insert(.calories) }
        if protein == nil { unreported.insert(.protein) }
        if carbs == nil { unreported.insert(.carbohydrates) }
        if fat == nil { unreported.insert(.fat) }

        // Sodium in mg; OFF stores grams. Salt converts at 2.5 g salt per 1 g sodium.
        let sodium = value("sodium_100g").map { $0 * 1000 } ?? value("salt_100g").map { $0 * 400 }

        var nutrition = NutritionFacts(
            calories: calories ?? 0,
            proteinGrams: protein ?? 0,
            carbohydrateGrams: carbs ?? 0,
            fatGrams: fat ?? 0,
            fiberGrams: value("fiber_100g"),
            sugarGrams: value("sugars_100g"),
            sodiumMilligrams: sodium,
            unreportedCoreNutrients: unreported.isEmpty ? nil : unreported
        )
        if let saturated = value("saturated-fat_100g") {
            nutrition.additional[.saturatedFat] = saturated
        }

        let unit = isLiquid(product) ? QuantityUnit.milliliter : .gram
        var servingOptions: [ServingOption] = []
        if let amount = number(product["serving_quantity"]), amount > 0 {
            let label = string(product["serving_size"]).flatMap { $0.isEmpty ? nil : $0 } ?? "1 serving"
            servingOptions.append(ServingOption(label: label, amount: amount))
        }

        let ingredients = string(product["ingredients_text"]).map { [$0] }?.filter { !$0.isEmpty } ?? []

        return Food(
            id: UUID(stableKey: "openfoodfacts.\(code)"),
            name: name,
            brand: string(product["brands"])?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) },
            barcode: code,
            servingSize: 100,
            servingUnit: unit,
            nutrition: nutrition,
            ingredients: ingredients,
            allergens: allergens(from: product["allergens_tags"]),
            quality: processingLevel(product["nova_group"]).map { FoodQuality(processingLevel: $0, additives: []) },
            source: .openFoodFacts,
            createdAt: retrievedAt,
            updatedAt: retrievedAt,
            servingOptions: servingOptions.isEmpty ? nil : servingOptions,
            sourceInfo: FoodSourceInfo(
                provider: "Open Food Facts",
                externalID: code,
                retrievedAt: retrievedAt,
                url: URL(string: productPageBase + code),
                license: OpenFoodFactsClient.licenseName,
                isCommunityContributed: true
            )
        )
    }

    // MARK: Field helpers

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let text as String: Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        default: nil
        }
    }

    static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    private static func firstNonEmpty(_ values: Any?...) -> String? {
        values.lazy.compactMap { string($0) }.first { !$0.isEmpty }
    }

    private static func isLiquid(_ product: [String: Any]) -> Bool {
        if let per = string(product["nutrition_data_per"])?.lowercased(), per.contains("ml") { return true }
        // Package size such as "330 ml", "33 cl", "1 l" or "1.5l".
        guard let quantity = string(product["quantity"])?.lowercased() else { return false }
        if quantity.contains("ml") || quantity.contains("cl") { return true }
        guard quantity.hasSuffix("l") else { return false }
        let amount = quantity.dropLast().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return Double(amount) != nil
    }

    private static func allergens(from value: Any?) -> Set<Allergen> {
        guard let tags = value as? [String] else { return [] }
        var result = Set<Allergen>()
        for tag in tags {
            switch tag.lowercased() {
            case "en:gluten": result.insert(.gluten)
            case "en:crustaceans": result.insert(.crustaceans)
            case "en:eggs": result.insert(.eggs)
            case "en:fish": result.insert(.fish)
            case "en:peanuts": result.insert(.peanuts)
            case "en:soybeans": result.insert(.soy)
            case "en:milk": result.insert(.milk)
            case "en:nuts": result.insert(.nuts)
            case "en:celery": result.insert(.celery)
            case "en:mustard": result.insert(.mustard)
            case "en:sesame-seeds": result.insert(.sesame)
            case "en:sulphur-dioxide-and-sulphites": result.insert(.sulphites)
            case "en:lupin": result.insert(.lupin)
            case "en:molluscs": result.insert(.molluscs)
            default: break
            }
        }
        return result
    }

    private static func processingLevel(_ value: Any?) -> ProcessingLevel? {
        switch number(value).map(Int.init) {
        case 1: .unprocessed
        case 2: .processedIngredient
        case 3: .processed
        case 4: .ultraProcessed
        default: nil
        }
    }
}
