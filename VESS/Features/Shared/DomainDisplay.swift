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

    /// When an entry added now to this meal on `day` is logged: now for
    /// today, otherwise the meal's typical time on that day.
    func logTime(on day: Date, now: Date = AppClock.now, calendar: Calendar) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let time = typicalTime
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}

nonisolated extension MealType: Identifiable {
    var id: Self { self }
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

extension DrinkCategory {
    var title: LocalizedStringResource {
        switch self {
        case .water: "Water"
        case .tea: "Tea"
        case .coffee: "Coffee"
        case .other: "Other"
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
        // The design's names; the stored values are unchanged.
        case .pantry: "Cupboard"
        case .other: "Counter"
        }
    }
}

extension CoreNutrient {
    var title: LocalizedStringResource {
        switch self {
        case .calories: "Calories"
        case .protein: "Protein"
        case .carbohydrates: "Carbs"
        case .fat: "Fat"
        }
    }

    /// Lowercase, for use mid-sentence ("protein", "carbs").
    var inlineName: LocalizedStringResource {
        switch self {
        case .calories: "calories"
        case .protein: "protein"
        case .carbohydrates: "carbs"
        case .fat: "fat"
        }
    }
}

extension Food {
    /// One honest line about where the values come from.
    var provenanceText: LocalizedStringResource {
        switch source {
        case .openFoodFacts: "Community data from Open Food Facts · not verified"
        case .starterCatalog: "Typical values from USDA FoodData Central"
        case .userCreated: "Your food"
        case .aiEstimate: "Estimate"
        case .foodDatabase, .barcodeScan: "Food database"
        }
    }

    /// The default portion as text, such as "1 medium (118 g)" or "100 g".
    var defaultPortionText: String {
        defaultPortion.text(unit: servingUnit)
    }
}

extension Portion {
    /// "1 medium (118 g)", "1.5 × 1 slice (48 g)" or "150 g".
    func text(unit: QuantityUnit) -> String {
        if option.isBaseUnit {
            return unit.amountText(count)
        }
        let total = unit.amountText(baseAmount)
        if count == 1 {
            return "\(option.label) (\(total))"
        }
        return "\(VESSFormat.quantity(count)) × \(option.label) (\(total))"
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

extension WorkoutType {
    var title: LocalizedStringResource {
        switch self {
        case .strength: "Strength"
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycle"
        case .hiit: "Intervals"
        case .yoga: "Yoga"
        case .mobility: "Mobility"
        case .swimming: "Swim"
        case .other: "Workout"
        }
    }

    /// Lowercase, for sentences: "Add 30-minute walk", "Walking most often".
    var activityNoun: LocalizedStringResource {
        switch self {
        case .strength: "strength"
        case .running: "running"
        case .walking: "walking"
        case .cycling: "cycling"
        case .hiit: "intervals"
        case .yoga: "yoga"
        case .mobility: "mobility"
        case .swimming: "swimming"
        case .other: "other workouts"
        }
    }

    /// The types offered when entering a workout (D03).
    static let enterable: [WorkoutType] = [.walking, .running, .cycling, .strength, .yoga, .swimming, .other]
}

extension WorkoutEffort {
    var title: LocalizedStringResource {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .hard: "Hard"
        }
    }

    /// "moderate effort".
    var phrase: LocalizedStringResource {
        switch self {
        case .easy: "easy effort"
        case .moderate: "moderate effort"
        case .hard: "hard effort"
        }
    }
}

extension QuantityUnit {
    /// Units counted as things, not measured: they take a plural.
    var isCountable: Bool { [.piece, .pack, .slice, .cup, .serving].contains(self) }

    /// "1 piece", "2 pieces", "1.5 slices", "150 g". Whole counts use the
    /// string catalog's plural rules; fractions take the plural form.
    func amountText(_ amount: Double) -> String {
        guard isCountable else { return "\(VESSFormat.quantity(amount)) \(String(localized: abbreviation))" }
        if let count = Int(exactly: amount) {
            switch self {
            case .piece: return String(localized: "\(count) piece")
            case .pack: return String(localized: "\(count) pack")
            case .slice: return String(localized: "\(count) slice")
            case .cup: return String(localized: "\(count) cup")
            default: return String(localized: "\(count) serving")
            }
        }
        let number = VESSFormat.quantity(amount)
        switch self {
        case .piece: return String(localized: "\(number) pieces")
        case .pack: return String(localized: "\(number) packs")
        case .slice: return String(localized: "\(number) slices")
        case .cup: return String(localized: "\(number) cups")
        default: return String(localized: "\(number) servings")
        }
    }
}
