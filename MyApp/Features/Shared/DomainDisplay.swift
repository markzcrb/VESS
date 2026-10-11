import SwiftUI

// User-facing names for domain values. Kept in the feature layer so the
// domain stays free of presentation and localization concerns.

extension MealType {
    var title: LocalizedStringResource {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .snack: "leaf"
        case .dinner: "moon"
        }
    }

    /// "Add dinner", for the Today suggestion row.
    var addTitle: LocalizedStringResource {
        switch self {
        case .breakfast: "Add breakfast"
        case .lunch: "Add lunch"
        case .dinner: "Add dinner"
        case .snack: "Add a snack"
        }
    }

    /// "Add to dinner", for Nutrition sections.
    var addToTitle: LocalizedStringResource {
        switch self {
        case .breakfast: "Add to breakfast"
        case .lunch: "Add to lunch"
        case .dinner: "Add to dinner"
        case .snack: "Add to snacks"
        }
    }

    /// A sensible time for an entry added to a past day.
    var typicalTime: DateComponents {
        switch self {
        case .breakfast: DateComponents(hour: 8, minute: 0)
        case .lunch: DateComponents(hour: 12, minute: 30)
        case .snack: DateComponents(hour: 16, minute: 0)
        case .dinner: DateComponents(hour: 19, minute: 30)
        }
    }
}

nonisolated extension MealType: Identifiable {
    var id: Self { self }
}

/// A request to open the Add food sheet for a meal on a day.
struct AddFoodRequest: Identifiable {
    let id = UUID()
    var meal: MealType
    var day: Date
}

extension WellnessGoal {
    var title: LocalizedStringResource {
        switch self {
        case .loseWeight: "Lose weight"
        case .maintainWeight: "Maintain weight"
        case .gainWeight: "Gain weight"
        case .buildMuscle: "Build muscle"
        case .eatHealthier: "Eat healthier"
        case .improveEnergy: "Improve energy"
        case .improveConsistency: "Improve consistency"
        }
    }
}

extension Sex {
    var title: LocalizedStringResource {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .notSpecified: "Prefer not to say"
        }
    }
}

extension ActivityLevel {
    var title: LocalizedStringResource {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Light"
        case .moderate: "Moderate"
        case .active: "Active"
        case .veryActive: "Very active"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .sedentary: "Mostly sitting, little exercise"
        case .light: "On your feet some of the day, or light exercise 1–3 days a week"
        case .moderate: "Exercise 3–5 days a week"
        case .active: "Hard exercise 6–7 days a week"
        case .veryActive: "Physical job or training twice a day"
        }
    }
}

extension DietaryPreference {
    var title: LocalizedStringResource {
        switch self {
        case .everything: "Everything"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .highProtein: "High protein"
        case .lowCarb: "Low carb"
        case .custom: "Something else"
        }
    }
}

extension Allergen {
    var title: LocalizedStringResource {
        switch self {
        case .gluten: "Gluten"
        case .lactose: "Lactose"
        case .nuts: "Nuts"
        case .soy: "Soy"
        case .eggs: "Eggs"
        }
    }
}

extension FocusArea {
    var title: LocalizedStringResource {
        switch self {
        case .nutrition: "Nutrition"
        case .fitness: "Fitness"
        case .energy: "Energy"
        case .hydration: "Hydration"
        case .budget: "Budget"
        case .foodWaste: "Food waste"
        case .mealPlanning: "Meal planning"
        }
    }
}

extension DrinkPreset {
    var title: LocalizedStringResource {
        switch self {
        case .water: "Water"
        case .sparklingWater: "Sparkling water"
        case .blackCoffee: "Black coffee"
        case .flatWhite: "Flat white"
        case .tea: "Tea"
        case .juice: "Juice"
        case .softDrink: "Soft drink"
        case .other: "Other drink"
        }
    }

    var symbol: String {
        switch self {
        case .water, .sparklingWater: "drop"
        case .blackCoffee, .flatWhite: "cup.and.saucer"
        case .tea: "mug"
        case .juice, .softDrink, .other: "takeoutbag.and.cup.and.straw"
        }
    }
}

extension DrinkType {
    var symbol: String {
        switch self {
        case .water: "drop"
        case .coffee: "cup.and.saucer"
        case .tea: "mug"
        case .juice, .softDrink, .energyDrink, .alcohol, .custom: "takeoutbag.and.cup.and.straw"
        }
    }
}

extension StorageLocation {
    var title: LocalizedStringResource {
        switch self {
        case .fridge: "Fridge"
        case .freezer: "Freezer"
        case .pantry: "Pantry"
        case .other: "Other"
        }
    }
}

extension QuantityUnit {
    /// Short unit label, such as "g" or "pcs".
    var abbreviation: LocalizedStringResource {
        switch self {
        case .gram: "g"
        case .kilogram: "kg"
        case .milliliter: "ml"
        case .liter: "L"
        case .piece: "pcs"
        case .pack: "pack"
        case .slice: "slice"
        case .cup: "cup"
        case .tablespoon: "tbsp"
        case .teaspoon: "tsp"
        case .serving: "serving"
        }
    }
}
