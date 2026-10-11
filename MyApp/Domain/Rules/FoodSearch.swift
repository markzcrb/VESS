import Foundation

/// Matching and ranking for food search. Pure and deterministic.
nonisolated enum FoodSearch {
    /// Lowercased, accent-folded, whitespace-normalized text for matching.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .joined(separator: " ")
    }

    /// The text a food is matched against: its name and brand.
    static func searchKey(for food: Food) -> String {
        normalized([food.name, food.brand].compactMap(\.self).joined(separator: " "))
    }

    /// Foods whose name or brand contains every word of `query`, best first:
    /// name starts with the query, then a word in the name starts with it,
    /// then favorites, then shorter names. Duplicate IDs keep the first copy.
    static func results(
        for query: String,
        in foods: [Food],
        favorites: Set<UUID> = [],
        limit: Int = 50
    ) -> [Food] {
        let terms = normalized(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }

        var seen = Set<UUID>()
        let unique = foods.filter { seen.insert($0.id).inserted }

        let matches = unique.compactMap { food -> (Food, Int)? in
            let key = searchKey(for: food)
            guard terms.allSatisfy({ key.contains($0) }) else { return nil }
            return (food, score(food: food, key: key, query: terms.joined(separator: " "), favorites: favorites))
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.name.count != rhs.0.name.count { return lhs.0.name.count < rhs.0.name.count }
                return lhs.0.name < rhs.0.name
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func score(food: Food, key: String, query: String, favorites: Set<UUID>) -> Int {
        let name = normalized(food.name)
        var score = 0
        if name.hasPrefix(query) { score += 100 }
        else if name.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { score += 50 }
        if favorites.contains(food.id) { score += 20 }
        return score
    }
}
