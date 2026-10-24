import Foundation

/// What a recipe the user makes, or an AI draft, contains, worked out from
/// its ingredients: allergens, contents and diet tags. Pure and
/// deterministic; matches the Discover data for every bundled ingredient.
nonisolated enum RecipeDerivation {
    /// Allergens an ingredient's name implies ("soy sauce" → soy, gluten;
    /// "pesto" → nuts, milk). Used where a source doesn't say (USDA, typed
    /// in) and to check an AI draft.
    static func allergens(forName name: String) -> Set<Allergen> {
        var result = Set<Allergen>()
        for (allergen, words) in AllergenKeywords.words {
            let exceptions = AllergenKeywords.exceptions[allergen] ?? []
            for word in words where IngredientMatcher.contains(word, in: name) {
                // "Coconut milk" isn't milk, unless milk is there on its own too.
                let excused = exceptions.contains { IngredientMatcher.contains($0, in: name) && IngredientMatcher.contains(word, in: $0) }
                if !excused { result.insert(allergen); break }
            }
        }
        return result
    }

    /// Allergens of a recipe: every ingredient's, plus those the user added.
    static func allergens(of ingredients: [Recipe.Ingredient], extra: Set<Allergen> = []) -> Set<Allergen> {
        ingredients.reduce(into: extra) { $0.formUnion($1.allergens) }
    }

    /// Meat, fish, dairy, egg, alcohol… from the names and the allergens.
    static func contents(of ingredients: [Recipe.Ingredient]) -> Set<Recipe.Content> {
        var result = Set<Recipe.Content>()
        for ingredient in ingredients {
            for content in Recipe.Content.allCases where ContentKeywords.matches(ingredient.name, content) {
                result.insert(content)
            }
            for allergen in ingredient.allergens {
                switch allergen {
                case .fish: result.insert(.fish)
                case .crustaceans: result.insert(.shellfish)
                case .molluscs: result.insert(.molluscs)
                case .milk: result.insert(.dairy)
                case .eggs: result.insert(.egg)
                default: break
                }
            }
        }
        return result
    }

    /// VG with nothing from animals (and no honey), V without meat or fish,
    /// P with fish but no meat, else O; GF without gluten, DF without milk.
    static func dietTags(contents: Set<Recipe.Content>, allergens: Set<Allergen>, ingredients: [Recipe.Ingredient]) -> Set<Recipe.DietTag> {
        let animal: Set<Recipe.Content> = [.meat, .poultry, .pork, .fish, .shellfish, .molluscs, .dairy, .egg]
        let flesh: Set<Recipe.Content> = [.meat, .poultry, .pork, .fish, .shellfish, .molluscs]
        let hasHoney = ingredients.contains { IngredientMatcher.contains("honey", in: $0.name) }
        var tags = Set<Recipe.DietTag>()
        if contents.isDisjoint(with: animal) && !hasHoney {
            tags.insert(.vegan)
        } else if contents.isDisjoint(with: flesh) {
            tags.insert(.vegetarian)
        } else if contents.isDisjoint(with: [.meat, .poultry, .pork]) {
            tags.insert(.pescatarian)
        } else {
            tags.insert(.omnivore)
        }
        if !allergens.contains(.gluten) { tags.insert(.glutenFree) }
        if !allergens.contains(.milk) { tags.insert(.dairyFree) }
        return tags
    }

    /// A user or AI recipe with everything worked out: allergens, contents,
    /// diet tags, nutrition per serving and high protein. `per100` looks up
    /// USDA foods.
    static func complete(_ recipe: Recipe, extraAllergens: Set<Allergen> = [], per100: (String) -> NutritionFacts?) -> (recipe: Recipe, isPartial: Bool) {
        var result = recipe
        let (nutrition, isPartial) = RecipeNutritionCalculator.perServing(ingredients: recipe.ingredients, servings: recipe.servings, per100: per100)
        result.nutrition = nutrition
        result.allergens = allergens(of: recipe.ingredients, extra: extraAllergens)
        result.contains = contents(of: recipe.ingredients)
        result.dietTags = dietTags(contents: result.contains, allergens: result.allergens, ingredients: recipe.ingredients)
        result.highProtein = RecipeNutritionCalculator.isHighProtein(nutrition)
        return (result, isPartial)
    }
}

/// Words for each of the 14 allergens, and look-alikes that aren't.
nonisolated enum AllergenKeywords {
    static let words: [Allergen: [String]] = [
        .gluten: ["wheat", "flour", "bread", "breadcrumbs", "pasta", "spaghetti", "penne", "fusilli", "couscous", "bulgur", "semolina",
                  "barley", "rye", "spelt", "soy sauce", "tortilla", "pita", "noodles", "oats", "oat", "granola", "muesli", "crispbread",
                  "sourdough", "bagel", "cracker", "biscuit", "seitan", "freekeh", "farro", "orzo", "gnocchi", "wholewheat", "wholemeal",
                  "wrap", "bun", "teriyaki", "oat drink"],
        .milk: ["milk", "cheese", "yogurt", "yoghurt", "cream", "butter", "ghee", "whey", "skyr", "quark", "tvaroh", "feta", "ricotta",
                "mozzarella", "parmesan", "halloumi", "kefir", "mascarpone", "cheddar", "paneer", "labneh", "creme fraiche", "custard", "pesto"],
        .eggs: ["egg", "mayonnaise", "mayo", "meringue"],
        .fish: ["fish", "cod", "salmon", "tuna", "trout", "mackerel", "sardine", "anchovy", "sea bass", "haddock", "herring", "pollock",
                "hake", "plaice", "fish sauce"],
        .crustaceans: ["prawn", "shrimp", "crab", "lobster", "langoustine", "crayfish"],
        .molluscs: ["mussel", "squid", "clam", "oyster", "scallop", "octopus", "calamari"],
        .peanuts: ["peanut", "satay"],
        .nuts: ["almond", "hazelnut", "walnut", "cashew", "pistachio", "pecan", "macadamia", "brazil nut", "pine nut", "pesto",
                "marzipan", "praline"],
        .soy: ["soy", "soya", "tofu", "tempeh", "edamame", "miso", "tamari", "soy sauce", "teriyaki"],
        .sesame: ["sesame", "tahini", "hummus", "halva"],
        .celery: ["celery", "celeriac", "stock cube", "stock", "bouillon"],
        .mustard: ["mustard"],
        .sulphites: ["wine", "dried apricot", "sulphite"],
        .lupin: ["lupin"],
    ]

    /// Names that contain an allergen word but aren't that allergen.
    static let exceptions: [Allergen: [String]] = [
        .gluten: ["buckwheat", "gluten-free", "chickpea flour", "gram flour", "rice flour", "corn flour", "cornflour", "corn tortilla",
                  "corn tortillas", "rice noodles", "rice paper", "corn tortilla chips", "buckwheat flakes", "tortilla chips"],
        .milk: ["coconut milk", "oat milk", "oat drink", "soy milk", "soy drink", "almond milk", "rice milk", "peanut butter",
                "almond butter", "cocoa butter", "butter beans", "butternut", "cream of tartar", "coconut cream", "butter lettuce",
                "soy yogurt", "coconut yogurt", "oat yogurt", "soy yoghurt"],
        .eggs: ["eggplant"],
        .nuts: ["coconut", "nutmeg", "butternut"],
        .celery: ["celery salt"],
    ]
}
