import Foundation

/// Discover (R01): search, meal chips, collections, the featured recipe and
/// the "N hidden" note. Pure and deterministic; every list respects
/// `RecipeFit`.
nonisolated enum RecipeDiscover {
    nonisolated struct Item: Identifiable, Hashable, Sendable {
        let recipe: Recipe
        let fit: RecipeFit
        var id: String { recipe.id }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.recipe.id == rhs.recipe.id && lhs.fit == rhs.fit }
        func hash(into hasher: inout Hasher) { hasher.combine(recipe.id) }
    }

    /// Meal chips: All, Breakfast, Lunch, Dinner, Snacks, Smoothies, Desserts.
    nonisolated enum MealFilter: CaseIterable, Sendable {
        case all, breakfast, lunch, dinner, snacks, smoothies, desserts

        func includes(_ category: RecipeCategory) -> Bool {
            switch self {
            case .all: true
            case .breakfast: category == .breakfast
            case .lunch: category == .lunch
            case .dinner: category == .dinner
            case .snacks: category == .snack
            case .smoothies: category == .smoothie
            case .desserts: category == .dessert
            }
        }
    }

    nonisolated enum Collection: CaseIterable, Sendable {
        case vegan, vegetarian, fishAndSeafood, glutenFree, dairyFree, highProtein, under20Minutes

        /// Quick: at most this many minutes, and no waiting on top.
        static let quickMinutes = 20

        func contains(_ recipe: Recipe) -> Bool {
            switch self {
            case .vegan: recipe.dietTags.contains(.vegan)
            case .vegetarian: !recipe.dietTags.isDisjoint(with: [.vegetarian, .vegan])
            case .fishAndSeafood: !recipe.contains.isDisjoint(with: [.fish, .shellfish, .molluscs])
            case .glutenFree: recipe.dietTags.contains(.glutenFree)
            case .dairyFree: recipe.dietTags.contains(.dairyFree)
            case .highProtein: recipe.highProtein
            case .under20Minutes: recipe.minutes <= Self.quickMinutes && recipe.extraTime == nil
            }
        }
    }

    /// Why recipes are hidden, for "Show why": "9 have nuts · 7 have meat".
    nonisolated enum HiddenGroup: Hashable, Sendable {
        case allergen(Allergen)
        /// Meat, poultry or pork.
        case meat
        case content(Recipe.Content)
        case notTagged(Diet)
        case meatWithDairy
        case avoid(String)
    }

    nonisolated struct HiddenSummary: Equatable, Sendable {
        /// Recipes not listed.
        let total: Int
        /// Each reason with how many hidden recipes have it, most first. A
        /// recipe with two reasons counts in both.
        let groups: [(group: HiddenGroup, count: Int)]

        static func == (lhs: HiddenSummary, rhs: HiddenSummary) -> Bool {
            lhs.total == rhs.total && lhs.groups.map(\.group) == rhs.groups.map(\.group) && lhs.groups.map(\.count) == rhs.groups.map(\.count)
        }
    }

    static func items(_ recipes: [Recipe], preferences: NutritionPreferences, allergies: Set<Allergen>) -> [Item] {
        recipes.map { recipe in
            let fit = RecipeFit.check(recipe, preferences: preferences, allergies: allergies)
            // Optional don't-eat ingredients are left out of what's shown and counted.
            return Item(recipe: recipe.without(fit.skipped), fit: fit)
        }
    }

    /// The list for a meal chip: fitting recipes first, ranked by the user's
    /// "also prefer" chips, then by name; with "Show recipes that don't fit"
    /// on, the others follow, greyed.
    static func listed(_ items: [Item], meal: MealFilter, preferences: NutritionPreferences) -> [Item] {
        items
            .filter { $0.fit.isListed(showNonFitting: preferences.showNonFittingRecipes) && meal.includes($0.recipe.category) }
            .sorted { lhs, rhs in
                if lhs.fit.fits != rhs.fit.fits { return lhs.fit.fits }
                let lhsBoost = RecipeFit.boost(lhs.recipe, preferences: preferences)
                let rhsBoost = RecipeFit.boost(rhs.recipe, preferences: preferences)
                if lhsBoost != rhsBoost { return lhsBoost > rhsBoost }
                return lhs.recipe.name.localizedStandardCompare(rhs.recipe.name) == .orderedAscending
            }
    }

    /// Search over names and ingredient names: every query word starts a
    /// word of either. Recipes that only have something the user doesn't eat
    /// still come up here, tagged ("Contains mushrooms"); allergens never do.
    static func search(_ query: String, in items: [Item], preferences: NutritionPreferences) -> [Item] {
        let terms = IngredientMatcher.words(query)
        guard !terms.isEmpty else { return [] }
        let matches = items.filter { item in
            guard item.fit.isListed(showNonFitting: preferences.showNonFittingRecipes) || item.fit.failsOnlyOnAvoid else { return false }
            let words = IngredientMatcher.words(([item.recipe.name] + item.recipe.ingredients.map(\.name)).joined(separator: " "))
            return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
        }
        return listed(matches, meal: .all, preferences: preferences.showingNonFitting)
    }

    /// Collections with at least one listed recipe, and how many fit ("14 for
    /// you").
    static func collections(_ items: [Item], preferences: NutritionPreferences) -> [(collection: Collection, count: Int)] {
        Collection.allCases.compactMap { collection in
            let count = items.count { $0.fit.isListed(showNonFitting: preferences.showNonFittingRecipes) && collection.contains($0.recipe) }
            return count > 0 ? (collection, count) : nil
        }
    }

    /// What isn't listed, and why.
    static func hidden(_ items: [Item], preferences: NutritionPreferences) -> HiddenSummary {
        let hidden = items.filter { !$0.fit.isListed(showNonFitting: preferences.showNonFittingRecipes) }
        var counts: [HiddenGroup: Int] = [:]
        var order: [HiddenGroup] = []
        for item in hidden {
            var groups: [HiddenGroup] = item.fit.allergens.sorted { $0.rawValue < $1.rawValue }.map { .allergen($0) }
            // With recipes that don't fit shown, only allergens hide one.
            for reason in item.fit.reasons where !preferences.showNonFittingRecipes {
                switch reason {
                case .has(let content, _): groups.append([.meat, .poultry, .pork].contains(content) ? .meat : .content(content))
                case .notTagged(let diet): groups.append(.notTagged(diet))
                case .meatWithDairy: groups.append(.meatWithDairy)
                case .avoid(let item): groups.append(.avoid(item))
                }
            }
            for group in Set(groups) {
                if counts[group] == nil { order.append(group) }
                counts[group, default: 0] += 1
            }
        }
        let sorted = order.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (counts[lhs.element] ?? 0, counts[rhs.element] ?? 0)
                return l != r ? l > r : lhs.offset < rhs.offset
            }
            .map { (group: $0.element, count: counts[$0.element] ?? 0) }
        return HiddenSummary(total: hidden.count, groups: sorted)
    }

    // MARK: Featured

    /// The next main meal from the usual meal times: still "next" until an
    /// hour after its time; after dinner, tomorrow's breakfast.
    static func nextMeal(now: Date, times: MealTimes, calendar: Calendar) -> (meal: MealType, day: Date) {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let today = calendar.startOfDay(for: now)
        let slots: [(MealType, Int)] = [(.breakfast, times.breakfast), (.lunch, times.lunch), (.dinner, times.dinner)]
        if let next = slots.first(where: { minute < $0.1 + slotGraceMinutes }) {
            return (next.0, today)
        }
        return (.breakfast, calendar.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    /// How long after its usual time a meal is still the next one.
    static let slotGraceMinutes = 60

    /// How many top recipes the featured card rotates through.
    static let featuredPool = 5

    /// The featured card: the top five fitting recipes for the next meal
    /// (most "also prefer" points, then most protein, then by name), one per
    /// day in turn, so it changes daily and stays the same all day.
    static func featured(_ items: [Item], meal: MealType, day: Date, preferences: NutritionPreferences, calendar: Calendar) -> Recipe? {
        let pool = items
            .filter { $0.fit.fits && $0.recipe.category.defaultMeal == meal }
            .map(\.recipe)
            .sorted { lhs, rhs in
                let (l, r) = (RecipeFit.boost(lhs, preferences: preferences), RecipeFit.boost(rhs, preferences: preferences))
                if l != r { return l > r }
                if lhs.nutrition.proteinGrams != rhs.nutrition.proteinGrams { return lhs.nutrition.proteinGrams > rhs.nutrition.proteinGrams }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(featuredPool)
        guard !pool.isEmpty, let dayNumber = calendar.ordinality(of: .day, in: .era, for: day) else { return pool.first }
        return pool[pool.startIndex + dayNumber % pool.count]
    }

    /// The usual meal times: the user's, else learned from the log, else
    /// 07:30 · 12:30 · 19:30.
    static func mealTimes(preferences: NutritionPreferences, learned: (MealType) -> DateComponents?) -> MealTimes {
        if let set = preferences.mealTimes { return set }
        func minutes(_ meal: MealType, _ fallback: Int) -> Int {
            guard let time = learned(meal) else { return fallback }
            return (time.hour ?? 0) * 60 + (time.minute ?? 0)
        }
        let standard = MealTimes.standard
        return MealTimes(breakfast: minutes(.breakfast, standard.breakfast), lunch: minutes(.lunch, standard.lunch), dinner: minutes(.dinner, standard.dinner))
    }
}

private extension NutritionPreferences {
    /// Search results are greyed rather than hidden.
    var showingNonFitting: NutritionPreferences {
        var copy = self
        copy.showNonFittingRecipes = true
        return copy
    }
}
