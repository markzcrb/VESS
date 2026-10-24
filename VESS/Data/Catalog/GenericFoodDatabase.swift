import Foundation
import Observation
import OSLog

/// A generic food from USDA FoodData Central, SR Legacy (public domain).
/// Values are per 100 g.
nonisolated struct GenericFood: Identifiable, Hashable, Sendable {
    /// USDA NDB number, such as "16358".
    let id: String
    let name: String
    let per100g: NutritionFacts
    /// Household portions in grams, such as "1 cup" = 164 g.
    let portions: [ServingOption]

    /// Grams first, then the household portions, as units for the amount
    /// stepper (R04).
    var units: [ServingOption] {
        [.baseUnit(.gram)] + portions
    }

    func nutrition(grams: Double) -> NutritionFacts {
        per100g.scaled(by: grams / 100)
    }
}

/// The bundled USDA table (8,422 generic foods). Read on first use, off the
/// main thread, and kept in memory; searched on the device.
@Observable
final class GenericFoodDatabase {
    private(set) var isLoaded = false
    private var index = GenericFoodIndex(foods: [])

    init(foods: [GenericFood]? = nil) {
        if let foods {
            index = GenericFoodIndex(foods: foods)
            isLoaded = true
        }
    }

    /// Reads the bundled file in the background; later calls do nothing.
    func load() async {
        guard !isLoaded else { return }
        do {
            index = try await Task.detached(priority: .userInitiated) { GenericFoodIndex(foods: try Self.bundled()) }.value
        } catch {
            Logger(subsystem: "VESS", category: "Foods").fault("Reading usda-sr-legacy.json failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoaded = true
    }

    /// Every food by NDB number.
    var table: [String: GenericFood] { index.byID }

    func food(ndb: String) -> GenericFood? {
        index.byID[ndb]
    }

    func search(_ query: String, limit: Int = 30) -> [GenericFood] {
        index.search(query, limit: limit)
    }

    /// The food for a pantry item's nutrition: the one the user chose, or
    /// else the best match for its name.
    func food(for item: InventoryItem) -> GenericFood? {
        item.genericFoodID.flatMap(food(ndb:)) ?? search(item.name, limit: 1).first
    }

    nonisolated static func bundled() throws -> [GenericFood] {
        guard let url = Bundle.main.url(forResource: "usda-sr-legacy", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    nonisolated static func decode(_ data: Data) throws -> [GenericFood] {
        try JSONDecoder().decode(Table.self, from: data).foods.map(\.food)
    }
}

/// Foods with their search words, built once.
nonisolated struct GenericFoodIndex: Sendable {
    private struct Entry: Sendable {
        let food: GenericFood
        /// Normalised words of the name, in order.
        let words: [String]
        /// Words before the first comma: USDA names start with the food
        /// itself ("Spinach, raw"; "Milk, whole").
        let headWords: [String]
        /// Comma-separated parts of the description ("Chickpeas, canned" is 2).
        let parts: Int
        let length: Int
        let isPlain: Bool
    }

    private let entries: [Entry]
    let byID: [String: GenericFood]

    init(foods: [GenericFood]) {
        entries = foods.map { food in
            let words = Self.words(food.name)
            return Entry(
                food: food,
                words: words,
                headWords: Self.words(String(food.name.prefix { $0 != "," })),
                parts: food.name.split(separator: ",").count,
                length: food.name.count,
                isPlain: words.contains { $0 == "raw" || $0 == "plain" }
            )
        }
        byID = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func words(_ text: String) -> [String] {
        IngredientMatcher.words(text)
    }

    private static func isWhole(_ word: String, _ term: String) -> Bool {
        IngredientMatcher.isWhole(word, term)
    }

    /// UK and EU names for what USDA calls something else. Each phrase is
    /// replaced in the query by its USDA words; longer phrases first.
    static let synonyms: [(phrase: String, usda: [String])] = [
        ("wholemeal bread", ["bread whole-wheat commercially prepared"]),
        ("baby spinach", ["spinach raw"]),
        ("spring onion", ["scallions", "onions spring"]),
        ("bok choy", ["pak-choi"]),
        ("jasmine rice", ["rice white long-grain"]),
        ("basmati rice", ["rice white long-grain"]),
        ("minced beef", ["ground beef"]),
        ("minced turkey", ["ground turkey"]),
        ("double cream", ["cream fluid heavy"]),
        ("single cream", ["cream fluid light table"]),
        ("icing sugar", ["sugars powdered"]),
        ("caster sugar", ["sugars granulated"]),
        ("plain flour", ["wheat flour white all-purpose"]),
        ("porridge oats", ["oats"]),
        ("rapeseed oil", ["oil canola"]),
        ("courgette", ["zucchini"]),
        ("aubergine", ["eggplant"]),
        ("coriander", ["cilantro", "coriander leaves"]),
        ("rocket", ["arugula"]),
        ("prawn", ["shrimp"]),
        ("beetroot", ["beets"]),
        ("chickpeas", ["chickpeas garbanzo"]),
        ("wholemeal", ["whole-wheat"]),
        ("swede", ["rutabagas"]),
        ("mangetout", ["peas edible-podded"]),
        ("sweetcorn", ["corn sweet"]),
        ("gherkin", ["pickles cucumber"]),
    ]

    /// Foods USDA has no match for: nothing is suggested, so the search
    /// falls through to Open Food Facts instead of a wrong generic food.
    static let noMatch: [String] = ["quark", "tvaroh", "skyr", "oat drink"]

    /// Every query word must start a word of the name ("chickpea" finds
    /// "Chickpeas"); foods missing one are left out. The original words
    /// come first, then their synonyms (`synonyms`):
    /// - original results with every query word in the food's own name (the
    ///   part before the first comma, "Coriander (cilantro) leaves, raw");
    /// - then the synonyms' results;
    /// - then the other original results ("Soup, cream of chicken" for
    ///   "single cream").
    /// Within each, best first (`ranked`).
    func search(_ query: String, limit: Int) -> [GenericFood] {
        let terms = Self.words(query)
        guard !terms.isEmpty, !Self.noMatch.contains(where: { Self.range(of: Self.words($0), in: terms) != nil }) else { return [] }
        let original = ranked(terms)
        let strong = original.filter { entry in terms.allSatisfy { term in entry.headWords.contains { Self.isWhole($0, term) } } }
        let weak = original.filter { entry in !strong.contains { $0.food.id == entry.food.id } }
        let alternatives = Self.synonyms
            .sorted { $0.phrase.count > $1.phrase.count }
            .flatMap { synonym -> [Entry] in
                guard let range = Self.range(of: Self.words(synonym.phrase), in: terms) else { return [] }
                return synonym.usda.flatMap { usda in
                    var replaced = terms
                    replaced.replaceSubrange(range, with: Self.words(usda))
                    return ranked(replaced)
                }
            }
        var seen = Set<String>()
        return (strong + alternatives + weak)
            .filter { seen.insert($0.food.id).inserted }
            .prefix(limit)
            .map(\.food)
    }

    private static func range(of phrase: [String], in terms: [String]) -> Range<Int>? {
        IngredientMatcher.range(of: phrase, in: terms)
    }

    /// Foods matching every term, best first:
    /// 1. every query word is a whole word ("egg" before "Eggplant");
    /// 2. the part before the first comma is the query, then contains it
    ///    ("Milk, whole" before "Milk and cereal bar");
    /// 3. the name starts with the first query word;
    /// 4. raw or plain forms;
    /// 5. shorter description: fewer comma-separated parts, then fewer
    ///    letters; then by name, so the order is stable.
    private func ranked(_ terms: [String]) -> [Entry] {
        entries
            .compactMap { entry -> (entry: Entry, key: [Int])? in
                guard terms.allSatisfy({ term in entry.words.contains { $0.hasPrefix(term) } }) else { return nil }
                let allWhole = terms.allSatisfy { term in entry.words.contains { Self.isWhole($0, term) } }
                let inHead = terms.allSatisfy { term in entry.headWords.contains { Self.isWhole($0, term) } }
                let headTier = inHead ? (entry.headWords.count == terms.count ? 0 : 1) : 2
                let startsWith = entry.words.first.map { Self.isWhole($0, terms[0]) } ?? false
                return (entry, [allWhole ? 0 : 1, headTier, startsWith ? 0 : 1, entry.isPlain ? 0 : 1, entry.parts, entry.length])
            }
            .sorted { lhs, rhs in
                if lhs.key != rhs.key { return lhs.key.lexicographicallyPrecedes(rhs.key) }
                return lhs.entry.food.name < rhs.entry.food.name
            }
            .map(\.entry)
    }
}

// MARK: - File format

/// `usda-sr-legacy.json`: per 100 g, short keys, up to two portions as
/// `[grams, label]`.
private nonisolated struct Table: Decodable {
    struct Row: Decodable {
        let id: String
        let name: String
        let kcal: Double
        let p: Double
        let c: Double
        let f: Double
        let fib: Double?
        let sug: Double?
        let na: Double?
        let sat: Double?
        let portions: [Portion]

        var food: GenericFood {
            var facts = NutritionFacts(
                calories: kcal, proteinGrams: p, carbohydrateGrams: c, fatGrams: f,
                fiberGrams: fib, sugarGrams: sug, sodiumMilligrams: na
            )
            if let sat { facts.additional[.saturatedFat] = sat }
            return GenericFood(
                id: id, name: name, per100g: facts,
                portions: portions.map { ServingOption(label: $0.label, amount: $0.grams) }
            )
        }
    }

    /// `[164.0, "1 cup"]`.
    struct Portion: Decodable {
        let grams: Double
        let label: String

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            grams = try container.decode(Double.self)
            label = try container.decode(String.self)
        }
    }

    let foods: [Row]
}
