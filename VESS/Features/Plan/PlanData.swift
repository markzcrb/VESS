import SwiftUI

/// What Plan suggests from: the user's own logged meals (last 28 days), the
/// Discover recipes and the user's own recipes that fit.
@MainActor
enum PlanCandidates {
    static let historyDays = 28

    static func all(store: LocalStore, catalog: RecipeCatalog, now: Date, calendar: Calendar) -> [MealSuggestions.Candidate] {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let start = calendar.date(byAdding: .day, value: -historyDays, to: end) ?? now
        let logged = MealSuggestions.Candidate.fromLog(
            store.foodEntries(from: start, to: end),
            allergens: { store.food(id: $0)?.allergens ?? [] },
            calendar: calendar
        )
        return logged + recipes(catalog, profile: store.profile, own: store.userRecipes)
    }

    /// Saved foods (favourites and your own), each as a one-item meal.
    static func saved(store: LocalStore) -> [MealSuggestions.Candidate] {
        var seen = Set<UUID>()
        return (store.favoriteFoods() + store.customFoods()).compactMap { food in
            guard seen.insert(food.id).inserted, food.nutrition.canBeLogged else { return nil }
            let amount = food.defaultPortion.baseAmount
            let nutrition = food.nutrition(forQuantity: amount)
            return MealSuggestions.Candidate(
                name: food.name,
                mealType: nil,
                nutrition: nutrition,
                items: [PlannedMeal.Item(name: food.name, quantity: amount, unit: food.servingUnit, foodID: food.id, nutrition: nutrition)],
                source: .foods,
                diets: nil,
                allergens: food.allergens
            )
        }
    }

    /// Recipes that fit the user (`RecipeFit`): diet, allergens and the
    /// ingredients they don't eat.
    static func recipes(_ catalog: RecipeCatalog, profile: UserProfile?, own: [Recipe] = []) -> [MealSuggestions.Candidate] {
        guard let profile else { return [] }
        return (catalog.recipes + own).compactMap { recipe in
            let fit = RecipeFit.check(recipe, preferences: profile.preferences, allergies: profile.allergies)
            return fit.fits ? MealSuggestions.Candidate(recipe: recipe.without(fit.skipped)) : nil
        }
    }
}

extension MealSuggestions.Reason {
    /// "Uses baby spinach before it expires", "Everything is in your pantry",
    /// "1 from your pantry · 2 to buy", "Adds 4 to grocery".
    var text: Text? {
        switch self {
        case .usesExpiring(let names):
            let list = names.map { $0.lowercased() }.formatted(.list(type: .and))
            return names.count == 1 ? Text("Uses \(list) before it expires") : Text("Uses \(list) before they expire")
        case .allInPantry: return Text("Everything is in your pantry")
        case .partly(let fromPantry, let toBuy): return Text("\(fromPantry) from your pantry · \(toBuy) to buy")
        case .toBuy(let count): return count > 0 ? Text("Adds \(count) to grocery") : nil
        }
    }
}

extension PantryMatch.Status {
    /// "Use soon · tomorrow", "In pantry", "To buy".
    var text: Text {
        switch self {
        case .useSoon(let expiry):
            if let relative = expiry.relativeText { return Text("Use soon · \(relative)") }
            return Text("Use soon")
        case .inPantry: return Text("In pantry")
        case .toBuy: return Text("To buy")
        }
    }
}

extension PlannedMeal.Item {
    /// "400 g", "2", or `nil` when the amount isn't known.
    var amountText: String? {
        guard let quantity else { return nil }
        guard let unit, unit != .piece else { return VESSFormat.quantity(quantity) }
        return unit.amountText(quantity)
    }
}

extension Recipe.Ingredient {
    /// "240 g", "2 cloves", "1 pinch", "3" for pieces, times `scale`;
    /// `nil` for "to taste".
    func amountText(scale: Double = 1) -> String? {
        guard let quantity else { return nil }
        let value = quantity * scale
        let number = VESSFormat.quantity(value)
        switch unit {
        case .clove: return value == 1 ? String(localized: "1 clove") : String(localized: "\(number) cloves")
        case .pinch: return value == 1 ? String(localized: "1 pinch") : String(localized: "\(number) pinches")
        case let unit?: return PlannedMeal.Item(name: name, quantity: value, unit: unit.quantityUnit).amountText
        case nil: return number
        }
    }
}

extension Calendar {
    /// The first day of the week containing `date`.
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}

/// Logs a planned meal as eaten, with Undo. Foods become one entry each;
/// a recipe becomes one entry for a serving.
@MainActor
enum PlanLogging {
    /// - Parameter markPlanned: records on the plan that it was logged;
    ///   `false` for a meal that was never planned ("Cook & log").
    static func log(_ meal: PlannedMeal, store: LocalStore, undo: FoodLogUndo, calendar: Calendar, markPlanned: Bool = true) throws {
        guard let profile = store.profile else { return }
        let time = meal.mealType.logTime(on: meal.day, calendar: calendar)
        let foodItems = meal.items.filter { $0.foodID != nil && $0.nutrition != nil }
        let entries: [FoodLogEntry]
        if case .foods = meal.source, !foodItems.isEmpty {
            entries = foodItems.map { item in
                FoodLogEntry(
                    id: UUID(), userID: profile.id, foodID: item.foodID, foodName: item.name, mealType: meal.mealType,
                    quantity: item.quantity ?? 1, servingUnit: item.unit ?? .serving,
                    nutrition: item.nutrition ?? .zero, loggedAt: time
                )
            }
        } else {
            entries = [FoodLogEntry(
                id: UUID(), userID: profile.id, foodID: nil, foodName: meal.name, mealType: meal.mealType,
                quantity: 1, servingUnit: .serving, nutrition: meal.nutrition, loggedAt: time,
                recipeID: { if case .recipe(let id) = meal.source { id } else { nil } }()
            )]
        }
        for entry in entries { try store.add(entry) }
        if markPlanned {
            var logged = meal
            logged.loggedAt = time
            try store.save(logged)
        }
        undo.show(entries, meal: meal.mealType)
    }
}
