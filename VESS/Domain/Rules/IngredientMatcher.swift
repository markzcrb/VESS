import Foundation

/// Word matching for ingredients: the avoid list, the pantry and USDA
/// search use the same rules. Case- and accent-insensitive, whole words,
/// simple plurals ("mushroom" matches "Mushrooms", "berry" "berries").
nonisolated enum IngredientMatcher {
    /// Normalised words of `text`.
    static func words(_ text: String) -> [String] {
        FoodSearch.normalized(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// `word` is `term`, or one is the other's simple plural.
    static func isWhole(_ word: String, _ term: String) -> Bool {
        if word == term { return true }
        return isPlural(word, of: term) || isPlural(term, of: word)
    }

    private static func isPlural(_ plural: String, of singular: String) -> Bool {
        plural == singular + "s" || plural == singular + "es"
            || (singular.hasSuffix("y") && plural == singular.dropLast() + "ies")
    }

    /// Where `phrase` appears in `terms`, word by word.
    static func range(of phrase: [String], in terms: [String]) -> Range<Int>? {
        guard !phrase.isEmpty, terms.count >= phrase.count else { return nil }
        for start in 0...(terms.count - phrase.count) where phrase.indices.allSatisfy({ isWhole(terms[start + $0], phrase[$0]) }) {
            return start..<(start + phrase.count)
        }
        return nil
    }

    /// Whether `phrase` appears in `text` as whole words ("blue cheese" in
    /// "Crumbled blue cheese").
    static func contains(_ phrase: String, in text: String) -> Bool {
        range(of: words(phrase), in: words(text)) != nil
    }

    /// A don't-eat item against an ingredient's pantry key and name.
    static func ingredient(_ ingredient: Recipe.Ingredient, contains phrase: String) -> Bool {
        contains(phrase, in: ingredient.name) || ingredient.key.map { contains(phrase, in: $0) } == true
    }

    /// A pantry item's name against an ingredient's key or name, either way
    /// round: "Rice" at home covers "Jasmine rice", and "Cod fillets" covers
    /// the key "cod".
    static func pantryName(_ name: String, matches ingredient: Recipe.Ingredient) -> Bool {
        let labels = [ingredient.key, ingredient.name].compactMap(\.self)
        return labels.contains { contains(name, in: $0) || contains($0, in: name) }
    }
}
