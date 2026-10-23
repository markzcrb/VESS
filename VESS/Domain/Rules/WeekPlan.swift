import Foundation

// Plan rules (PRODUCT-LOGIC.md #9, decided 2026-10-20). Pure and deterministic.

/// A week of main meals (breakfast, lunch, dinner): what was eaten, what's
/// planned, and what's still open.
nonisolated struct WeekPlan: Sendable {
    nonisolated enum Slot: Sendable {
        case eaten([FoodLogEntry])
        case planned(PlannedMeal)
        case open
    }

    nonisolated struct Day: Sendable {
        let date: Date
        let isPast: Bool
        let isToday: Bool
        /// Breakfast, lunch, dinner.
        let slots: [(meal: MealType, slot: Slot)]
        /// Everything logged that day, snacks included.
        let logged: [FoodLogEntry]

        /// How many main meals are eaten or planned (17, 18: the day's dot).
        var filledCount: Int {
            slots.filter { if case .open = $0.slot { false } else { true } }.count
        }

        /// The day's dot: filled for all main meals, hollow for some, none
        /// for nothing.
        var coverage: Coverage {
            let filled = filledCount
            if filled == 0 { return .none }
            return filled == slots.count ? .all : .some
        }
    }

    nonisolated enum Coverage: Equatable, Sendable {
        case none, some, all
    }

    static let slotsPerDay = MealType.mainMeals

    let days: [Day]
    /// Slots eaten or planned, of `slotCount`.
    let filledCount: Int
    let slotCount: Int
    /// Open slots from today on, in order.
    let openSlots: [(day: Date, meal: MealType)]

    init(weekStart: Date, entries: [FoodLogEntry], planned: [PlannedMeal], now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        var days: [Day] = []
        var filled = 0
        var open: [(day: Date, meal: MealType)] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: weekStart)) else { continue }
            let logged = entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
            let slots = Self.slotsPerDay.map { meal -> (meal: MealType, slot: Slot) in
                let eaten = logged.filter { $0.mealType == meal }
                if !eaten.isEmpty { return (meal, .eaten(eaten)) }
                // A plan logged and then undone shows again: only entries count as eaten.
                if let plan = planned.first(where: { calendar.isDate($0.day, inSameDayAs: date) && $0.mealType == meal }) {
                    return (meal, .planned(plan))
                }
                return (meal, .open)
            }
            for (meal, slot) in slots {
                switch slot {
                case .eaten, .planned: filled += 1
                case .open: if date >= today { open.append((date, meal)) }
                }
            }
            days.append(Day(date: date, isPast: date < today, isToday: date == today, slots: slots, logged: logged))
        }
        self.days = days
        self.filledCount = filled
        self.slotCount = days.count * Self.slotsPerDay.count
        self.openSlots = open
    }
}

/// Matches meal ingredients to what's at home, by name.
nonisolated enum PantryMatch {
    nonisolated enum Status: Equatable, Sendable {
        /// At home and expiring within the 3-day threshold.
        case useSoon(ExpirationStatus)
        case inPantry
        case toBuy
    }

    /// The pantry item for an ingredient: the longest name that contains, or
    /// is contained in, the ingredient's name ("Cod fillets" ↔ "Cod fillets",
    /// "Jasmine rice" ↔ "Rice").
    static func item(for name: String, in pantry: [InventoryItem]) -> InventoryItem? {
        let wanted = FoodSearch.normalized(name)
        guard !wanted.isEmpty else { return nil }
        return pantry
            .filter { $0.status == .available }
            .filter {
                let have = FoodSearch.normalized($0.name)
                return !have.isEmpty && (wanted.contains(have) || have.contains(wanted))
            }
            .max { $0.name.count < $1.name.count }
    }

    static func status(for name: String, in pantry: [InventoryItem], now: Date, calendar: Calendar) -> Status {
        guard let item = item(for: name, in: pantry) else { return .toBuy }
        let expiry = item.expirationStatus(now: now, calendar: calendar)
        return expiry.needsAttention ? .useSoon(expiry) : .inPantry
    }
}

/// Fills open slots (PRODUCT-LOGIC.md #9): only meals that fit the slot,
/// the user's diet and allergies; preferring what uses pantry items before
/// they expire, then what's at home, then protein near a third of the
/// day's target. A meal is suggested at most once a week.
nonisolated enum MealSuggestions {
    nonisolated struct Candidate: Hashable, Sendable {
        let name: String
        /// The slot it suits; `nil` for any.
        let mealType: MealType?
        let nutrition: NutritionFacts
        let items: [PlannedMeal.Item]
        let source: PlannedMeal.Source
        /// Recipe diets; `nil` for the user's own logged meals.
        let diets: Set<Recipe.Diet>?
        let allergens: Set<Allergen>
    }

    nonisolated enum Reason: Equatable, Sendable {
        /// Uses these pantry items before they expire.
        case usesExpiring([String])
        case allInPantry
        case partly(fromPantry: Int, toBuy: Int)
        case toBuy(Int)
    }

    nonisolated struct Suggestion: Sendable {
        let day: Date
        let meal: MealType
        let candidate: Candidate
        let reason: Reason
    }

    /// One suggestion per open slot, where something fits.
    static func suggest(
        openSlots: [(day: Date, meal: MealType)],
        candidates: [Candidate],
        pantry: [InventoryItem],
        profile: UserProfile,
        excludingNames: Set<String> = [],
        now: Date,
        calendar: Calendar
    ) -> [Suggestion] {
        var used = Set(excludingNames.map(FoodSearch.normalized))
        var result: [Suggestion] = []
        for slot in openSlots {
            let options = ranked(for: slot.meal, on: slot.day, candidates: candidates, pantry: pantry, profile: profile, now: now, calendar: calendar)
            guard let best = options.first(where: { !used.contains(FoodSearch.normalized($0.name)) }) else { continue }
            used.insert(FoodSearch.normalized(best.name))
            result.append(Suggestion(
                day: slot.day, meal: slot.meal, candidate: best,
                reason: reason(best, day: slot.day, pantry: pantry, now: now, calendar: calendar)
            ))
        }
        return result
    }

    /// Candidates for one slot, best first (A02 "Good fits for this slot").
    static func ranked(
        for meal: MealType,
        on day: Date,
        candidates: [Candidate],
        pantry: [InventoryItem],
        profile: UserProfile,
        now: Date,
        calendar: Calendar
    ) -> [Candidate] {
        let proteinPerMeal = profile.nutritionTargets.proteinGrams / Double(WeekPlan.slotsPerDay.count)
        let suitable = candidates.filter { candidate in
            let slotFits = candidate.mealType == nil || candidate.mealType == meal
            return slotFits && fits(diets: candidate.diets, profile: profile) && candidate.allergens.isDisjoint(with: profile.allergies)
        }
        let scored: [(candidate: Candidate, score: Double)] = suitable.map { candidate in
            (candidate, score(candidate, day: day, pantry: pantry, proteinPerMeal: proteinPerMeal, now: now, calendar: calendar))
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.candidate.name.localizedStandardCompare(rhs.candidate.name) == .orderedAscending
            }
            .map(\.candidate)
    }

    /// Whether a recipe's diets suit the user. The user's own logged meals
    /// (`nil`) always do. A custom diet is matched by its description.
    static func fits(diets: Set<Recipe.Diet>?, profile: UserProfile) -> Bool {
        guard let diets else { return true }
        switch profile.dietaryPreference {
        case .vegan: return diets.contains(.vegan)
        case .vegetarian: return !diets.isDisjoint(with: [.vegetarian, .vegan])
        case .custom:
            let description = FoodSearch.normalized(profile.customDietDescription ?? "")
            if description.contains("vegan") { return diets.contains(.vegan) }
            if description.contains("vegetarian") { return !diets.isDisjoint(with: [.vegetarian, .vegan]) }
            if description.contains("pescatarian") { return !diets.isDisjoint(with: [.pescatarian, .vegetarian, .vegan]) }
            return true
        case .everything, .highProtein, .lowCarb: return true
        }
    }

    /// Pantry items the candidate uses that expire soon (from now), but
    /// not before `day`.
    static func expiringUsed(by candidate: Candidate, day: Date, pantry: [InventoryItem], now: Date, calendar: Calendar) -> [InventoryItem] {
        var seen = Set<UUID>()
        return candidate.items.compactMap { item -> InventoryItem? in
            guard let match = PantryMatch.item(for: item.name, in: pantry), !seen.contains(match.id),
                  let expiry = match.expirationDate,
                  calendar.startOfDay(for: expiry) >= calendar.startOfDay(for: day),
                  match.expirationStatus(now: now, calendar: calendar).needsAttention
            else { return nil }
            seen.insert(match.id)
            return match
        }
    }

    private static func score(_ candidate: Candidate, day: Date, pantry: [InventoryItem], proteinPerMeal: Double, now: Date, calendar: Calendar) -> Double {
        let expiring = Double(expiringUsed(by: candidate, day: day, pantry: pantry, now: now, calendar: calendar).count)
        let inPantry = candidate.items.filter { PantryMatch.item(for: $0.name, in: pantry) != nil }.count
        let pantryShare = candidate.items.isEmpty ? 0 : Double(inPantry) / Double(candidate.items.count)
        var proteinFit = 0.0
        if candidate.nutrition.isReported(.protein), proteinPerMeal > 0 {
            proteinFit = max(0, 1 - abs(candidate.nutrition.proteinGrams - proteinPerMeal) / proteinPerMeal)
        }
        return expiring * 3 + pantryShare + proteinFit
    }

    static func reason(_ candidate: Candidate, day: Date, pantry: [InventoryItem], now: Date, calendar: Calendar) -> Reason {
        let expiring = expiringUsed(by: candidate, day: day, pantry: pantry, now: now, calendar: calendar)
        if !expiring.isEmpty { return .usesExpiring(expiring.map(\.name)) }
        let fromPantry = candidate.items.filter { PantryMatch.item(for: $0.name, in: pantry) != nil }.count
        let toBuy = candidate.items.count - fromPantry
        if toBuy == 0, fromPantry > 0 { return .allInPantry }
        if fromPantry == 0 { return .toBuy(toBuy) }
        return .partly(fromPantry: fromPantry, toBuy: toBuy)
    }
}

nonisolated extension MealSuggestions.Candidate {
    /// A recipe as a plan candidate, one serving.
    init(recipe: Recipe) {
        self.init(
            name: recipe.name,
            mealType: recipe.mealType,
            nutrition: recipe.nutrition,
            items: recipe.ingredients.map {
                PlannedMeal.Item(
                    name: $0.name,
                    quantity: $0.quantity.map { $0 / Double(max(recipe.servings, 1)) },
                    unit: $0.unit
                )
            },
            source: .recipe(recipe.id),
            diets: recipe.diets,
            allergens: recipe.allergens
        )
    }

    /// The user's own meals: each day's logged entries for a slot, once per
    /// distinct set of foods, most recent first. Quick adds are left out.
    static func fromLog(_ entries: [FoodLogEntry], allergens: (UUID) -> Set<Allergen>, calendar: Calendar) -> [Self] {
        let grouped = Dictionary(grouping: entries) { entry in
            "\(calendar.startOfDay(for: entry.loggedAt).timeIntervalSince1970)|\(entry.mealType.rawValue)"
        }
        var seen = Set<String>()
        return grouped.values
            .map { $0.sorted { $0.loggedAt < $1.loggedAt } }
            .sorted { ($0.first?.loggedAt ?? .distantPast) > ($1.first?.loggedAt ?? .distantPast) }
            .compactMap { meal -> Self? in
                guard let first = meal.first, meal.allSatisfy({ $0.foodID != nil }) else { return nil }
                let names = meal.map(\.foodName)
                let key = FoodSearch.normalized(names.sorted().joined(separator: " "))
                guard seen.insert(key).inserted else { return nil }
                return Self(
                    name: Self.mealName(names),
                    mealType: first.mealType,
                    nutrition: meal.totalNutrition,
                    items: meal.map {
                        PlannedMeal.Item(name: $0.foodName, quantity: $0.quantity, unit: $0.servingUnit, foodID: $0.foodID, nutrition: $0.nutrition)
                    },
                    source: .foods,
                    diets: nil,
                    allergens: meal.compactMap(\.foodID).reduce(into: Set<Allergen>()) { $0.formUnion(allergens($1)) }
                )
            }
    }

    /// "Greek yogurt, oats, blueberries".
    static func mealName(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        return ([first] + names.dropFirst().map { $0.lowercased() }).joined(separator: ", ")
    }
}

nonisolated extension PlannedMeal {
    /// A plan entry for `candidate` on `day`.
    init(candidate: MealSuggestions.Candidate, day: Date, meal: MealType, now: Date, calendar: Calendar) {
        self.init(
            id: UUID(), day: calendar.startOfDay(for: day), mealType: meal, name: candidate.name,
            nutrition: candidate.nutrition, items: candidate.items, source: candidate.source,
            loggedAt: nil, createdAt: now
        )
    }
}
