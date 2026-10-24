import Foundation
import Testing
@testable import VESS

@Suite("Recipes: nutrition, fit, Discover and AI Chef")
struct RecipeRulesTests {
    static let recipes = MockData.catalogRecipes
    static let usda: [String: NutritionFacts] = Dictionary(
        ((try? GenericFoodDatabase.bundled()) ?? []).map { ($0.id, $0.per100g) }, uniquingKeysWith: { first, _ in first }
    )
    private let calendar = TestClock.utc

    private func recipe(_ id: String) throws -> Recipe {
        try #require(Self.recipes.first { $0.id == id })
    }

    /// Mark: pescatarian, high-protein, nut-free, no coriander, mushrooms or blue cheese.
    private let mark = NutritionPreferences(diet: .pescatarian, alsoPrefer: [.highProtein], avoidIngredients: ["Coriander", "Mushrooms", "Blue cheese"])
    private let markAllergies: Set<Allergen> = [.nuts, .peanuts]

    private func ingredient(_ name: String, grams: Double?, per100: NutritionFacts?, allergens: Set<Allergen> = [], optional: Bool = false) -> Recipe.Ingredient {
        Recipe.Ingredient(name: name, key: name.lowercased(), quantity: grams, unit: .gram, grams: grams, allergens: allergens, source: .user, per100: per100, isOptional: optional)
    }

    private func make(_ name: String, category: RecipeCategory = .dinner, minutes: Int = 25, kcal: Double = 500, protein: Double = 30,
                      ingredients: [Recipe.Ingredient] = [], tags: Set<Recipe.DietTag> = [.pescatarian], contains: Set<Recipe.Content> = [.fish],
                      highProtein: Bool = true) -> Recipe {
        Recipe(
            id: name, name: name, category: category, minutes: minutes, extraTime: nil, servings: 2,
            nutrition: NutritionFacts(calories: kcal, proteinGrams: protein, carbohydrateGrams: 40, fatGrams: 15),
            ingredients: ingredients, steps: ["Cook."], tip: nil, dietTags: tags, tags: [], highProtein: highProtein,
            contains: contains, allergens: ingredients.reduce(into: Set<Allergen>()) { $0.formUnion($1.allergens) },
            photo: nil, origin: .user, createdAt: nil
        )
    }

    private func pantryItem(_ name: String, expiresIn days: Int? = nil, now: Date) -> InventoryItem {
        InventoryItem(
            id: UUID(), name: name, quantity: 1, unit: .piece, purchaseDate: nil,
            expirationDate: days.flatMap { calendar.date(byAdding: .day, value: $0, to: now) },
            category: .other, location: .fridge, notes: nil, status: .available, reminderSnoozedUntil: nil
        )
    }

    // MARK: Nutrition

    @Test("The calculator reproduces every Discover recipe's nutrition (±1 kcal, ±0.1 g, ±1 mg), unknowns included")
    func reproducesCatalog() {
        #expect(Self.recipes.count == 122)
        for recipe in Self.recipes {
            let (calculated, isPartial) = RecipeNutritionCalculator.perServing(ingredients: recipe.ingredients, servings: recipe.servings) { Self.usda[$0] }
            let expected = recipe.nutrition
            #expect(!isPartial, "\(recipe.id)")
            #expect(abs(calculated.calories - expected.calories) <= 1, "\(recipe.id) kcal")
            for (name, a, b) in [("protein", calculated.proteinGrams, expected.proteinGrams), ("carbs", calculated.carbohydrateGrams, expected.carbohydrateGrams), ("fat", calculated.fatGrams, expected.fatGrams)] {
                #expect(abs(a - b) <= 0.1 + 1e-9, "\(recipe.id) \(name) \(a) vs \(b)")
            }
            for (name, a, b, tolerance) in [
                ("fibre", calculated.fiberGrams, expected.fiberGrams, 0.1), ("sugar", calculated.sugarGrams, expected.sugarGrams, 0.1),
                ("sodium", calculated.sodiumMilligrams, expected.sodiumMilligrams, 1),
                ("saturated fat", calculated.additional[.saturatedFat], expected.additional[.saturatedFat], 0.1),
            ] {
                #expect((a == nil) == (b == nil), "\(recipe.id) \(name) known")
                if let a, let b { #expect(abs(a - b) <= tolerance + 1e-9, "\(recipe.id) \(name) \(a) vs \(b)") }
            }
            #expect(RecipeNutritionCalculator.isHighProtein(expected) == recipe.highProtein, "\(recipe.id) high protein")
        }
    }

    @Test("Unknown fibre on one ingredient leaves fibre unknown; an ingredient without data makes the total partial")
    func unknowns() {
        let known = NutritionFacts(calories: 100, proteinGrams: 10, carbohydrateGrams: 10, fatGrams: 2, fiberGrams: 3, sugarGrams: 1, sodiumMilligrams: 50)
        var noFibre = known
        noFibre.fiberGrams = nil
        let (total, partial) = RecipeNutritionCalculator.perServing(
            ingredients: [ingredient("Beans", grams: 200, per100: known), ingredient("Sauce", grams: 100, per100: noFibre)], servings: 2
        ) { _ in nil }
        #expect(!partial && total.calories == 150 && total.proteinGrams == 15)
        #expect(total.fiberGrams == nil && total.sugarGrams == 1.5 && total.sodiumMilligrams == 75)

        let (withMissing, isPartial) = RecipeNutritionCalculator.perServing(
            ingredients: [ingredient("Beans", grams: 200, per100: known), ingredient("Mystery", grams: 50, per100: nil)], servings: 1
        ) { _ in nil }
        #expect(isPartial && withMissing.calories == 200 && withMissing.fiberGrams == nil)
    }

    @Test("High protein: 20 g, or 15 g that is 30 % of the energy")
    func highProtein() {
        func facts(_ kcal: Double, _ protein: Double) -> NutritionFacts { NutritionFacts(calories: kcal, proteinGrams: protein, carbohydrateGrams: 0, fatGrams: 0) }
        #expect(RecipeNutritionCalculator.isHighProtein(facts(800, 20)))
        #expect(RecipeNutritionCalculator.isHighProtein(facts(200, 15)))
        #expect(!RecipeNutritionCalculator.isHighProtein(facts(201, 15)))
        #expect(!RecipeNutritionCalculator.isHighProtein(facts(100, 14.9)))
    }

    // MARK: Fit

    @Test("Allergens are a hard filter, even with \"Show recipes that don't fit\" on")
    func allergenHardFilter() throws {
        var showAll = mark
        showAll.showNonFittingRecipes = true
        let cashew = try recipe("018-tempeh-and-peanut-noodle-salad")
        let fit = RecipeFit.check(cashew, preferences: showAll, allergies: markAllergies)
        #expect(fit.isBlocked && !fit.isListed(showNonFitting: true) && !fit.failsOnlyOnAvoid)
        let items = RecipeDiscover.items(Self.recipes, preferences: showAll, allergies: markAllergies)
        #expect(!RecipeDiscover.listed(items, meal: .all, preferences: showAll).contains { !$0.recipe.allergens.isDisjoint(with: markAllergies) })
        #expect(RecipeDiscover.search("peanut", in: items, preferences: showAll).allSatisfy { $0.recipe.allergens.isDisjoint(with: markAllergies) })
    }

    @Test("Pescatarian: no meat, poultry or pork; the reason names the ingredient")
    func pescatarian() throws {
        let chicken = try recipe("011-chicken-quinoa-and-roasted-veg-bowl")
        let fit = RecipeFit.check(chicken, preferences: NutritionPreferences(diet: .pescatarian), allergies: [])
        #expect(fit.reasons == [.has(.poultry, ingredient: "chicken breast")])
        #expect(!fit.isBlocked && fit.isListed(showNonFitting: true) && !fit.isListed(showNonFitting: false))
        #expect(RecipeFit.check(try recipe(MockData.tonightRecipeID), preferences: NutritionPreferences(diet: .pescatarian), allergies: []).fits)
        let pork = try recipe("029-pork-tenderloin-with-apple-and-red-cabbage")
        #expect(!RecipeFit.check(pork, preferences: NutritionPreferences(diet: .pescatarian), allergies: []).fits)
    }

    @Test("Vegan needs the VG tag; vegetarian V or VG; flexitarian and no restrictions don't filter")
    func vegan() throws {
        let cod = try recipe(MockData.tonightRecipeID)
        let oats = try recipe("001-overnight-oats-with-berries-and-chia")
        #expect(RecipeFit.check(oats, preferences: NutritionPreferences(diet: .vegan), allergies: []).fits)
        #expect(RecipeFit.check(cod, preferences: NutritionPreferences(diet: .vegan), allergies: []).reasons == [.has(.fish, ingredient: "cod fillets, skinless")])
        #expect(!RecipeFit.check(cod, preferences: NutritionPreferences(diet: .vegetarian), allergies: []).fits)
        #expect(RecipeFit.check(cod, preferences: NutritionPreferences(diet: .flexitarian), allergies: []).fits)
        let honeyless = make("Plain oats", tags: [], contains: [])
        #expect(RecipeFit.check(honeyless, preferences: NutritionPreferences(diet: .vegan), allergies: []).reasons == [.notTagged(.vegan)])
        for recipe in Self.recipes where RecipeFit.check(recipe, preferences: NutritionPreferences(diet: .vegan), allergies: []).fits {
            #expect(recipe.contains.isDisjoint(with: [.meat, .poultry, .pork, .fish, .shellfish, .molluscs, .dairy, .egg]), "\(recipe.id)")
        }
    }

    @Test("Halal: no pork or alcohol. Kosher: no pork, shellfish or molluscs, no meat with dairy")
    func halalKosher() throws {
        let halal = NutritionPreferences(alsoPrefer: [.halal])
        let kosher = NutritionPreferences(alsoPrefer: [.kosher])
        let pork = try recipe("029-pork-tenderloin-with-apple-and-red-cabbage")
        let miso = try recipe(MockData.tonightRecipeID)
        let mussels = try recipe("078-mussels-in-tomato-and-garlic")
        #expect(RecipeFit.check(pork, preferences: halal, allergies: []).reasons.contains { if case .has(.pork, _) = $0 { true } else { false } })
        #expect(RecipeFit.check(miso, preferences: halal, allergies: []).reasons == [.has(.alcohol, ingredient: "mirin")])
        #expect(RecipeFit.check(miso, preferences: kosher, allergies: []).fits)
        #expect(!RecipeFit.check(mussels, preferences: kosher, allergies: []).fits)
        #expect(RecipeFit.check(mussels, preferences: halal, allergies: []).fits || mussels.contains.contains(.alcohol))
        let cheeseburger = make("Cheeseburger", contains: [.meat, .dairy])
        #expect(RecipeFit.check(cheeseburger, preferences: kosher, allergies: []).reasons == [.meatWithDairy])
        #expect(!RecipeFit.check(make("Chicken", contains: [.poultry]), preferences: kosher, allergies: []).reasons.contains(.meatWithDairy))
    }

    @Test("Don't-eat items match key and name as whole words, with plurals, ignoring case and accents")
    func avoidMatching() {
        let mushrooms = make("Risotto", ingredients: [ingredient("Chestnut Mushrooms", grams: 200, per100: nil)], tags: [.vegetarian], contains: [])
        let prefs = NutritionPreferences(avoidIngredients: ["mushroom"])
        #expect(RecipeFit.check(mushrooms, preferences: prefs, allergies: []).reasons == [.avoid("mushroom")])
        #expect(RecipeFit.check(mushrooms, preferences: NutritionPreferences(avoidIngredients: ["MUSHRÓOMS"]), allergies: []).failsOnlyOnAvoid)
        let peanut = make("Satay", ingredients: [ingredient("Peanut sauce", grams: 50, per100: nil)])
        #expect(RecipeFit.check(peanut, preferences: NutritionPreferences(avoidIngredients: ["pea"]), allergies: []).fits, "Whole words only")
        let berries = make("Bowl", ingredients: [ingredient("Mixed berries", grams: 80, per100: nil)])
        #expect(!RecipeFit.check(berries, preferences: NutritionPreferences(avoidIngredients: ["berry"]), allergies: []).fits)
        let cheese = make("Salad", ingredients: [ingredient("Crumbled blue cheese", grams: 30, per100: nil)])
        #expect(!RecipeFit.check(cheese, preferences: NutritionPreferences(avoidIngredients: ["Blue cheese"]), allergies: []).fits)
        #expect(RecipeFit.check(cheese, preferences: NutritionPreferences(avoidIngredients: ["blue"]), allergies: []).fits == false)
    }

    @Test("An optional don't-eat ingredient is skipped: the recipe stays, without it and its nutrition")
    func optionalAvoid() throws {
        let guacamole = try recipe("091-guacamole-with-corn-tortilla-chips")
        let coriander = try #require(guacamole.ingredients.first { $0.name == "Fresh coriander" })
        #expect(coriander.isOptional && coriander.per100 != nil)
        let fit = RecipeFit.check(guacamole, preferences: mark, allergies: markAllergies)
        #expect(fit.fits && fit.skipped == ["Coriander"])
        let cooked = guacamole.without(fit.skipped)
        #expect(cooked.ingredients.count == guacamole.ingredients.count - 1)
        let expected = guacamole.nutrition.calories - (coriander.per100?.calories ?? 0) * (coriander.grams ?? 0) / 100 / Double(guacamole.servings)
        #expect(abs(cooked.nutrition.calories - expected) < 0.001 && cooked.nutrition.calories < guacamole.nutrition.calories)
        // Recalculating without it gives the same total, within the data's rounding.
        let recalculated = RecipeNutritionCalculator.perServing(ingredients: cooked.ingredients, servings: cooked.servings) { Self.usda[$0] }.nutrition
        #expect(abs(recalculated.calories - cooked.nutrition.calories) <= 1)
        #expect(abs(recalculated.proteinGrams - cooked.nutrition.proteinGrams) <= 0.1)
        #expect(cooked.allergens == guacamole.allergens)

        let items = RecipeDiscover.items(Self.recipes, preferences: mark, allergies: markAllergies)
        let listed = try #require(RecipeDiscover.listed(items, meal: .all, preferences: mark).first { $0.recipe.id == guacamole.id })
        #expect(listed.fit.skipped == ["Coriander"] && !listed.recipe.ingredients.contains { $0.name == "Fresh coriander" })
    }

    @Test("A don't-eat item that isn't optional still hides; an optional allergen still hides everywhere")
    func requiredAvoidAndOptionalAllergen() throws {
        let both = make("Herb rice", ingredients: [
            ingredient("Coriander", grams: 20, per100: nil), ingredient("Coriander leaves", grams: 5, per100: nil, optional: true),
        ], tags: [.vegan], contains: [])
        let fit = RecipeFit.check(both, preferences: mark, allergies: [])
        #expect(!fit.fits && fit.reasons == [.avoid("Coriander")] && fit.skipped.isEmpty)
        #expect(!RecipeFit.check(try recipe("026-mushroom-and-lentil-shepherd-s-pie"), preferences: mark, allergies: []).fits)

        let topping = make("Yogurt bowl", ingredients: [
            ingredient("Greek yogurt", grams: 150, per100: nil, allergens: [.milk]),
            ingredient("Chopped hazelnuts", grams: 10, per100: nil, allergens: [.nuts], optional: true),
        ], tags: [.vegetarian], contains: [.dairy])
        var showAll = mark
        showAll.showNonFittingRecipes = true
        let blocked = RecipeFit.check(topping, preferences: showAll, allergies: markAllergies)
        #expect(blocked.isBlocked && !blocked.isListed(showNonFitting: true))
        #expect(topping.without(["hazelnuts"]).allergens.contains(.nuts), "Skipping never removes an allergen")
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        #expect(AIChef.rank([topping], preferences: showAll, allergies: markAllergies, pantry: [], remaining: .init(proteinGrams: 30, calories: 900), now: now, calendar: calendar).isEmpty)
        let items = RecipeDiscover.items([topping], preferences: showAll, allergies: markAllergies)
        #expect(RecipeDiscover.search("yogurt", in: items, preferences: showAll).isEmpty)
    }

    @Test("AI Chef leaves a skipped ingredient out of have and missing")
    func chefSkips() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let guacamole = try recipe("091-guacamole-with-corn-tortilla-chips")
        let match = try #require(AIChef.rank([guacamole], preferences: mark, allergies: markAllergies, pantry: [pantryItem("Avocados", expiresIn: 1, now: now)],
                                             remaining: .init(proteinGrams: 30, calories: 900), now: now, calendar: calendar).first)
        let names = (match.pantry.have.map(\.ingredient) + match.pantry.missing + match.pantry.missingOptional).map(\.name)
        #expect(!names.contains("Fresh coriander"))
        #expect(match.pantry.useSoon.map(\.name) == ["Avocados"])
    }

    @Test("Also-prefer chips rank, never hide")
    func boosts() throws {
        let prefs = NutritionPreferences(alsoPrefer: [.highProtein, .glutenFree, .lowerCarb])
        let cod = try recipe(MockData.tonightRecipeID)
        #expect(RecipeFit.check(cod, preferences: prefs, allergies: []).fits)
        #expect(RecipeFit.boost(cod, preferences: prefs) >= 1)
        #expect(RecipeFit.boost(make("Lean", highProtein: false), preferences: NutritionPreferences(alsoPrefer: [.lowerCarb])) == 0)
        #expect(RecipeFit.boost(make("Veg", tags: [.vegetarian], contains: []), preferences: NutritionPreferences(diet: .flexitarian)) == 1)
    }

    @Test("Plan suggestions only offer recipes that fit, including the avoid list")
    @MainActor
    func planSuggestions() throws {
        var profile = MockData(now: .now, calendar: calendar).profile
        profile.nutritionPreferences = mark
        profile.allergies = markAllergies
        let candidates = PlanCandidates.recipes(RecipeCatalog(recipes: Self.recipes), profile: profile)
        #expect(!candidates.isEmpty)
        let names = Set(candidates.map(\.name))
        #expect(!names.contains("Chicken, quinoa and roasted veg bowl"))
        #expect(names.contains("Miso-glazed cod with greens"))
        let guacamole = try #require(candidates.first { $0.name == "Guacamole with corn tortilla chips" }, "Coriander is optional")
        #expect(!guacamole.items.contains { $0.name.localizedCaseInsensitiveContains("coriander") }, "Nothing to buy for it")
    }

    // MARK: Discover

    @Test("R01 for Mark: 31 of 122 hidden; Show why counts each reason")
    func hiddenNote() {
        let items = RecipeDiscover.items(Self.recipes, preferences: mark, allergies: markAllergies)
        let hidden = RecipeDiscover.hidden(items, preferences: mark)
        // Coriander is only ever an optional garnish: those recipes stay, without it.
        #expect(hidden.total == 31)
        let counts = Dictionary(uniqueKeysWithValues: hidden.groups.map { ($0.group, $0.count) })
        #expect(counts == [.meat: 21, .allergen(.nuts): 5, .allergen(.peanuts): 4, .avoid("Mushrooms"): 1])
        #expect(hidden.groups.first?.group == .meat)
        #expect(RecipeDiscover.listed(items, meal: .all, preferences: mark).count == 91)

        var showAll = mark
        showAll.showNonFittingRecipes = true
        let shown = RecipeDiscover.hidden(items, preferences: showAll)
        #expect(shown.total == 9 && shown.groups.allSatisfy { if case .allergen = $0.group { true } else { false } })
        let listed = RecipeDiscover.listed(items, meal: .all, preferences: showAll)
        #expect(listed.count == 113)
        #expect(listed.prefix(91).allSatisfy(\.fit.fits) && listed.dropFirst(91).allSatisfy { !$0.fit.fits }, "Greyed ones after")
    }

    @Test("Search covers names and ingredients; don't-eat recipes still open from search, allergens never")
    func search() {
        let items = RecipeDiscover.items(Self.recipes, preferences: mark, allergies: markAllergies)
        let mushroom = RecipeDiscover.search("mushroom", in: items, preferences: mark)
        #expect(mushroom.map(\.recipe.id).contains("026-mushroom-and-lentil-shepherd-s-pie"))
        #expect(mushroom.first { $0.recipe.id == "026-mushroom-and-lentil-shepherd-s-pie" }?.fit.reasons == [.avoid("Mushrooms")])
        #expect(!RecipeDiscover.search("chicken", in: items, preferences: mark).contains { !$0.fit.fits && !$0.fit.failsOnlyOnAvoid }, "Diet failures stay hidden")
        #expect(RecipeDiscover.search("bok", in: items, preferences: mark).contains { $0.recipe.id == MockData.tonightRecipeID }, "Ingredient words")
        #expect(RecipeDiscover.search("", in: items, preferences: mark).isEmpty)
    }

    @Test("Meal chips and collections respect the fit; empty collections hide")
    func chipsAndCollections() throws {
        let items = RecipeDiscover.items(Self.recipes, preferences: mark, allergies: markAllergies)
        #expect(RecipeDiscover.listed(items, meal: .smoothies, preferences: mark).allSatisfy { $0.recipe.category == .smoothie })
        let collections = RecipeDiscover.collections(items, preferences: mark)
        #expect(collections.map(\.collection) == RecipeDiscover.Collection.allCases)
        for (collection, count) in collections {
            #expect(count == items.count { $0.fit.fits && collection.contains($0.recipe) })
        }
        let veganOnly = RecipeDiscover.items(Self.recipes.filter { $0.dietTags.contains(.vegan) }, preferences: NutritionPreferences(diet: .vegan), allergies: [])
        #expect(!RecipeDiscover.collections(veganOnly, preferences: NutritionPreferences(diet: .vegan)).contains { $0.collection == .fishAndSeafood })
        #expect(RecipeDiscover.Collection.under20Minutes.contains(make("Quick", minutes: 20)))
        #expect(!RecipeDiscover.Collection.under20Minutes.contains(try recipe("001-overnight-oats-with-berries-and-chia")), "Overnight isn't quick")
    }

    @Test("Featured: the next meal by the usual times; the same all day, changing across days")
    func featured() throws {
        let times = MealTimes.standard
        let evening = try TestClock.date(2026, 10, 6, 18, 40)
        #expect(RecipeDiscover.nextMeal(now: evening, times: times, calendar: calendar).meal == .dinner)
        #expect(RecipeDiscover.nextMeal(now: try TestClock.date(2026, 10, 6, 8, 20), times: times, calendar: calendar).meal == .breakfast)
        #expect(RecipeDiscover.nextMeal(now: try TestClock.date(2026, 10, 6, 8, 31), times: times, calendar: calendar).meal == .lunch)
        let late = RecipeDiscover.nextMeal(now: try TestClock.date(2026, 10, 6, 21, 0), times: times, calendar: calendar)
        #expect(late.meal == .breakfast && calendar.component(.day, from: late.day) == 7)

        let items = RecipeDiscover.items(Self.recipes, preferences: mark, allergies: markAllergies)
        let day = calendar.startOfDay(for: evening)
        let first = RecipeDiscover.featured(items, meal: .dinner, day: day, preferences: mark, calendar: calendar)
        let again = RecipeDiscover.featured(items, meal: .dinner, day: day.addingTimeInterval(3600), preferences: mark, calendar: calendar)
        #expect(first != nil && first == again)
        #expect(first?.category == .dinner && first?.highProtein == true)
        // Five days in a row: five different dinners from the top five, then again.
        let days = (0..<10).compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
            .compactMap { RecipeDiscover.featured(items, meal: .dinner, day: $0, preferences: mark, calendar: calendar)?.id }
        #expect(Set(days.prefix(5)).count == 5)
        #expect(Array(days.prefix(5)) == Array(days.suffix(5)))
        // One recipe leading on points doesn't repeat every day.
        let leader = make("Leader", kcal: 600, protein: 60)
        let others = (1...6).map { make("Other \($0)", protein: Double(20 + $0), highProtein: false) }
        let pool = RecipeDiscover.items([leader] + others, preferences: mark, allergies: [])
        let picks = (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
            .compactMap { RecipeDiscover.featured(pool, meal: .dinner, day: $0, preferences: mark, calendar: calendar)?.name }
        #expect(picks.count { $0 == "Leader" } == 1 && Set(picks).count == 5)
        #expect(!picks.contains("Other 1"), "Only the top five: Leader, then the most protein")
    }

    @Test("Meal times: the user's, else learned, else 07:30 · 12:30 · 19:30")
    func mealTimes() {
        let learned = RecipeDiscover.mealTimes(preferences: NutritionPreferences()) { $0 == .lunch ? DateComponents(hour: 13, minute: 15) : nil }
        #expect(learned == MealTimes(breakfast: 450, lunch: 795, dinner: 1170))
        let set = MealTimes(breakfast: 420, lunch: 720, dinner: 1080)
        #expect(RecipeDiscover.mealTimes(preferences: NutritionPreferences(mealTimes: set)) { _ in DateComponents(hour: 9) } == set)
    }

    // MARK: AI Chef

    @Test("AI Chef ranks a fixed pantry: use-soon items, then share at home, then today's remaining targets")
    func chefRanking() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let pantry = [
            pantryItem("Baby spinach", expiresIn: 1, now: now), pantryItem("Bok choy", expiresIn: 2, now: now),
            pantryItem("White miso", now: now), pantryItem("Mirin", now: now), pantryItem("Jasmine rice", now: now),
            pantryItem("Garlic", now: now), pantryItem("Eggs", now: now), pantryItem("Tofu", now: now),
        ]
        let codGreens = make("A cod and greens", ingredients: [
            ingredient("Cod fillets", grams: 300, per100: nil, allergens: [.fish]), ingredient("Baby spinach", grams: 100, per100: nil),
            ingredient("Bok choy", grams: 200, per100: nil), ingredient("Salt", grams: 0, per100: nil),
        ])
        let spinachEggs = make("B spinach eggs", category: .lunch, kcal: 400, protein: 28, ingredients: [
            ingredient("Baby spinach", grams: 100, per100: nil), ingredient("Eggs", grams: 150, per100: nil, allergens: [.eggs]),
        ], tags: [.vegetarian], contains: [.egg])
        let riceBowl = make("C rice bowl", kcal: 450, protein: 25, ingredients: [
            ingredient("Jasmine rice", grams: 150, per100: nil), ingredient("Garlic", grams: 6, per100: nil),
        ], tags: [.vegan], contains: [])
        let riceHeavy = make("D rice feast", kcal: 1400, protein: 25, ingredients: [
            ingredient("Jasmine rice", grams: 300, per100: nil), ingredient("Garlic", grams: 6, per100: nil),
        ], tags: [.vegan], contains: [])
        let chicken = make("E chicken", ingredients: [ingredient("Chicken breast", grams: 300, per100: nil), ingredient("Baby spinach", grams: 100, per100: nil)], contains: [.poultry])
        let coriander = make("F coriander rice", ingredients: [ingredient("Jasmine rice", grams: 150, per100: nil), ingredient("Coriander", grams: 10, per100: nil, optional: true)], tags: [.vegan], contains: [])

        var showAll = mark
        showAll.showNonFittingRecipes = true
        let ranked = AIChef.rank(
            [riceHeavy, riceBowl, chicken, coriander, spinachEggs, codGreens], preferences: showAll, allergies: markAllergies,
            pantry: pantry, remaining: .init(proteinGrams: 26, calories: 900), now: now, calendar: calendar
        )
        // Cod uses two use-soon items; eggs one; then the rice bowls, all at
        // home, within energy (closest to the protein left) before over it.
        // Chicken is never used (diet, even with the toggle on); the coriander
        // rice comes without its optional coriander.
        #expect(ranked.map(\.recipe.name) == ["A cod and greens", "B spinach eggs", "C rice bowl", "F coriander rice", "D rice feast"])
        #expect(ranked.first { $0.recipe.name == "F coriander rice" }?.recipe.ingredients.map(\.name) == ["Jasmine rice"])

        let cod = try #require(ranked.first)
        #expect(cod.pantry.atHomeCount == 2 && cod.pantry.countedTotal == 3, "Salt doesn't count")
        #expect(cod.pantry.useSoon.map(\.name) == ["Baby spinach", "Bok choy"])
        #expect(cod.pantry.missing.map(\.name) == ["Cod fillets"])
        #expect(cod.swaps.map(\.replacement) == ["tofu"], "Swap cod for tofu")

        let filtered = AIChef.rank(
            [codGreens, spinachEggs, riceBowl], preferences: mark, allergies: markAllergies, pantry: pantry,
            remaining: .init(proteinGrams: 26, calories: 900), filters: .init(meal: .dinner, usesUseSoon: true), now: now, calendar: calendar
        )
        #expect(filtered.map(\.recipe.name) == ["A cod and greens"])
    }

    @Test("Swaps only from the table, only when at home, only when the swap still fits")
    func swaps() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let cod = make("Cod", ingredients: [ingredient("Cod fillets", grams: 300, per100: nil, allergens: [.fish])])
        let withTofu = [pantryItem("Firm tofu", now: now)]
        #expect(AIChef.rank([cod], preferences: mark, allergies: markAllergies, pantry: withTofu, remaining: .init(proteinGrams: 40, calories: 900), now: now, calendar: calendar)
            .first?.swaps.map(\.replacement) == ["tofu"])
        // Soy allergy: tofu would break it.
        #expect(AIChef.rank([cod], preferences: mark, allergies: [.soy], pantry: withTofu, remaining: .init(proteinGrams: 40, calories: 900), now: now, calendar: calendar)
            .first?.swaps.isEmpty == true)
        // Salmon at home: cod → salmon.
        #expect(AIChef.rank([cod], preferences: mark, allergies: [], pantry: [pantryItem("Salmon fillet", now: now)], remaining: .init(proteinGrams: 40, calories: 900), now: now, calendar: calendar)
            .first?.swaps.map(\.replacement) == ["salmon"])
        // Nothing in the table: no swap.
        let leek = make("Leek", ingredients: [ingredient("Leek", grams: 200, per100: nil)], tags: [.vegan], contains: [])
        #expect(AIChef.rank([leek], preferences: mark, allergies: [], pantry: [pantryItem("Onions", now: now)], remaining: .init(proteinGrams: 40, calories: 900), now: now, calendar: calendar)
            .first?.swaps.isEmpty == true)
        // A swap keeps the recipe's other allergens and drops the fish one.
        let swapped = AIChef.swapping(cod.ingredients[0], from: AIChef.swapGroups[0][0], to: AIChef.swapGroups[0][2], in: cod)
        #expect(swapped.allergens == [.soy] && !swapped.contains.contains(.fish))
    }

    @Test("Expired items aren't at home; use-soon is the 3-day threshold")
    func pantryStatus() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let recipe = make("Greens", ingredients: [ingredient("Spinach", grams: 100, per100: nil), ingredient("Kale", grams: 100, per100: nil), ingredient("Leek", grams: 100, per100: nil)], tags: [.vegan], contains: [])
        let use = AIChef.pantryUse(recipe, pantry: [
            pantryItem("Spinach", expiresIn: -1, now: now), pantryItem("Kale", expiresIn: 3, now: now), pantryItem("Leeks", expiresIn: 4, now: now),
        ], now: now, calendar: calendar)
        #expect(use.have.map(\.item.name) == ["Kale", "Leeks"])
        #expect(use.useSoon.map(\.name) == ["Kale"])
        #expect(use.missing.map(\.name) == ["Spinach"])
    }
}
