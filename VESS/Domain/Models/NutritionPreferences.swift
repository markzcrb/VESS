import Foundation

/// The one diet a user follows (P01, "Diet · one").
nonisolated enum Diet: String, Codable, CaseIterable, Sendable {
    case noRestrictions
    case pescatarian
    case vegetarian
    case vegan
    case flexitarian
}

/// "Also prefer · any" on P01. Ranking boosts, not filters, except that
/// halal and kosher are checked from the ingredients.
nonisolated enum FoodPreference: String, Codable, CaseIterable, Sendable {
    case highProtein
    case lowerCarb
    case mediterranean
    case glutenFree
    case dairyFree
    case halal
    case kosher
}

/// The usual times of the three main meals, in minutes after midnight.
nonisolated struct MealTimes: Codable, Hashable, Sendable {
    var breakfast: Int
    var lunch: Int
    var dinner: Int

    /// 07:30 · 12:30 · 19:30.
    static let standard = MealTimes(breakfast: 7 * 60 + 30, lunch: 12 * 60 + 30, dinner: 19 * 60 + 30)
}

/// What the user eats (P01). Allergies stay on `UserProfile.allergies`.
nonisolated struct NutritionPreferences: Codable, Hashable, Sendable {
    var diet: Diet
    var alsoPrefer: Set<FoodPreference>
    /// Ingredients the user doesn't eat, as typed ("Coriander"), without
    /// duplicates. Matching is case- and accent-insensitive.
    var avoidIngredients: [String]
    /// Show recipes that don't fit the diet or avoid list, greyed with the
    /// reason. Allergens are never shown.
    var showNonFittingRecipes: Bool
    /// `nil` until the user sets them: then the times learned from the log,
    /// or `MealTimes.standard`.
    var mealTimes: MealTimes?

    init(diet: Diet = .noRestrictions, alsoPrefer: Set<FoodPreference> = [], avoidIngredients: [String] = [], showNonFittingRecipes: Bool = false, mealTimes: MealTimes? = nil) {
        self.diet = diet
        self.alsoPrefer = alsoPrefer
        self.avoidIngredients = Self.normalizedAvoidList(avoidIngredients)
        self.showNonFittingRecipes = showNonFittingRecipes
        self.mealTimes = mealTimes
    }

    /// Trims and collapses spaces, drops empty entries and duplicates
    /// (ignoring case and accents), keeps the first spelling.
    static func normalizedAvoidList(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            let tidy = item.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !tidy.isEmpty, seen.insert(FoodSearch.normalized(tidy)).inserted else { return nil }
            return tidy
        }
    }

    /// The diet the target calculator knows. It has one value: high protein
    /// wins over lower carb when both are preferred.
    var targetDiet: DietaryPreference {
        if alsoPrefer.contains(.highProtein) { return .highProtein }
        if alsoPrefer.contains(.lowerCarb) { return .lowCarb }
        return .everything
    }
}

// MARK: - Migration from earlier builds

extension UserProfile {
    /// Preferences as saved, or as migrated from the earlier diet fields.
    nonisolated var preferences: NutritionPreferences {
        nutritionPreferences ?? Self.migrated(self).nutritionPreferences ?? NutritionPreferences()
    }

    /// Moves a profile from an earlier build to `NutritionPreferences`.
    /// Profiles that already have them are returned unchanged.
    ///
    /// - vegetarian → vegetarian, vegan → vegan, everything → no restrictions,
    ///   high protein → no restrictions + high protein, low carb → no
    ///   restrictions + lower carb.
    /// - Custom text naming a diet ("Pescatarian") sets that diet.
    ///   Otherwise one ingredient ("no coriander") goes to the avoid list;
    ///   anything longer stays in `customDietDescription`. The same for
    ///   each of `otherRestrictions`.
    /// - "Nuts" in earlier builds also covered peanuts (Open Food Facts'
    ///   peanut tag mapped to it), so peanuts are added to keep the filter.
    /// The earlier fields stay stored as they were.
    nonisolated static func migrated(_ profile: UserProfile) -> UserProfile {
        guard profile.nutritionPreferences == nil else { return profile }
        var result = profile
        var preferences = NutritionPreferences()
        var avoid: [String] = []
        var kept: [String] = []

        switch profile.dietaryPreference {
        case .everything: break
        case .vegetarian: preferences.diet = .vegetarian
        case .vegan: preferences.diet = .vegan
        case .highProtein: preferences.alsoPrefer.insert(.highProtein)
        case .lowCarb: preferences.alsoPrefer.insert(.lowerCarb)
        case .custom:
            let text = profile.customDietDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let diet = namedDiet(in: text) {
                preferences.diet = diet
                if !isOnlyDietName(text) { kept.append(text) }
            } else if let ingredient = singleIngredient(text) {
                avoid.append(ingredient)
            } else if !text.isEmpty {
                kept.append(text)
            }
        }
        for restriction in profile.otherRestrictions {
            let text = restriction.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ingredient = singleIngredient(text) {
                avoid.append(ingredient)
            } else if !text.isEmpty {
                kept.append(text)
            }
        }

        preferences.avoidIngredients = NutritionPreferences.normalizedAvoidList(avoid)
        result.nutritionPreferences = preferences
        result.customDietDescription = kept.isEmpty ? nil : kept.joined(separator: "; ")
        if result.allergies.contains(.nuts) { result.allergies.insert(.peanuts) }
        return result
    }

    private nonisolated static let dietWords: [(word: String, diet: Diet)] = [
        ("pescatarian", .pescatarian), ("pescetarian", .pescatarian),
        ("vegan", .vegan), ("vegetarian", .vegetarian), ("flexitarian", .flexitarian),
    ]

    private nonisolated static func namedDiet(in text: String) -> Diet? {
        let words = Set(FoodSearch.normalized(text).split { !$0.isLetter }.map(String.init))
        return dietWords.first { words.contains($0.word) }?.diet
    }

    /// "Pescatarian" or "pescatarian diet", nothing more.
    private nonisolated static func isOnlyDietName(_ text: String) -> Bool {
        let words = FoodSearch.normalized(text).split { !$0.isLetter }.map(String.init).filter { $0 != "diet" }
        return words.count == 1 && dietWords.contains { $0.word == words[0] }
    }

    /// "Coriander", "no mushrooms", "blue cheese": at most two words of
    /// letters, after a leading "no", "without" or "avoid". `nil` for
    /// anything else ("no spicy food, please", "mostly plants and fish").
    private nonisolated static func singleIngredient(_ text: String) -> String? {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if let first = words.first, ["no", "without", "avoid"].contains(first.lowercased()) { words.removeFirst() }
        guard (1...2).contains(words.count),
              words.allSatisfy({ $0.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" } }),
              !words.contains(where: { ["and", "or", "&"].contains($0.lowercased()) }) else { return nil }
        let joined = words.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}
