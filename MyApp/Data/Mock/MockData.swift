#if DEBUG
import Foundation

/// SAMPLE DATA, for Xcode Previews, unit tests and UI tests only.
///
/// Compiled into Debug builds only, so it can never appear in a release
/// build. In a Debug run it is loaded only when the app is launched with
/// `-seedSampleData` (see `VESSApp`). Production screens start empty.
///
/// All dates are relative to `now`, so "expires tomorrow" stays true whenever
/// it runs. Pass a fixed date and calendar in tests.
nonisolated struct MockData: Sendable {
    let profile: UserProfile
    let foods: [Food]
    let foodLog: [FoodLogEntry]
    let drinks: [Drink]
    let hydrationLog: [HydrationLog]
    let workouts: [Workout]
    let inventory: [InventoryItem]
    let supplements: [Supplement]
    let supplementLog: [SupplementLog]
    let weightHistory: [WeightEntry]
    let insights: [Insight]

    static let preview = MockData(now: .now, calendar: .current)

    init(now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today) ?? today
        }

        let userID = UUID()

        // MARK: Profile

        profile = UserProfile(
            id: userID,
            name: "Alex",
            dateOfBirth: calendar.date(byAdding: .year, value: -29, to: today),
            sex: .male,
            heightCentimeters: 178,
            weightKilograms: 68,
            goalWeightKilograms: 72,
            goal: .buildMuscle,
            activityLevel: .moderate,
            dietaryPreference: .highProtein,
            customDietDescription: nil,
            allergies: [],
            otherRestrictions: [],
            focusAreas: [.nutrition, .fitness, .foodWaste],
            nutritionTargets: NutritionTargets(
                calories: 2550,
                proteinGrams: 135,
                carbohydrateGrams: 320,
                fatGrams: 80
            ),
            waterTargetMilliliters: 2300,
            createdAt: day(-21),
            updatedAt: day(-1)
        )

        // MARK: Foods (values per serving)

        func food(
            _ name: String,
            brand: String? = nil,
            serving: Double,
            unit: QuantityUnit,
            kcal: Double,
            protein: Double,
            carbs: Double,
            fat: Double,
            fiber: Double? = nil,
            sugar: Double? = nil,
            allergens: Set<Allergen> = [],
            processing: ProcessingLevel = .unprocessed
        ) -> Food {
            Food(
                id: UUID(),
                name: name,
                brand: brand,
                barcode: nil,
                servingSize: serving,
                servingUnit: unit,
                nutrition: NutritionFacts(
                    calories: kcal,
                    proteinGrams: protein,
                    carbohydrateGrams: carbs,
                    fatGrams: fat,
                    fiberGrams: fiber,
                    sugarGrams: sugar
                ),
                ingredients: [],
                allergens: allergens,
                quality: FoodQuality(processingLevel: processing, additives: []),
                source: .foodDatabase,
                createdAt: day(-21),
                updatedAt: day(-21)
            )
        }

        let oats = food("Rolled oats", serving: 40, unit: .gram, kcal: 150, protein: 5.3, carbs: 27, fat: 2.6, fiber: 4, sugar: 0.4, allergens: [.gluten])
        let yogurt = food("Greek yogurt 2%", serving: 170, unit: .gram, kcal: 124, protein: 17, carbs: 6.6, fat: 3.4, sugar: 6.6, allergens: [.lactose], processing: .processed)
        let strawberries = food("Strawberries", serving: 100, unit: .gram, kcal: 32, protein: 0.7, carbs: 7.7, fat: 0.3, fiber: 2, sugar: 4.9)
        let chicken = food("Chicken breast, grilled", serving: 100, unit: .gram, kcal: 165, protein: 31, carbs: 0, fat: 3.6)
        let rice = food("Jasmine rice, cooked", serving: 100, unit: .gram, kcal: 130, protein: 2.7, carbs: 28, fat: 0.3, fiber: 0.4)
        let avocado = food("Avocado", serving: 100, unit: .gram, kcal: 160, protein: 2, carbs: 8.5, fat: 14.7, fiber: 6.7, sugar: 0.7)
        let almonds = food("Almonds", serving: 28, unit: .gram, kcal: 164, protein: 6, carbs: 6, fat: 14.2, fiber: 3.5, sugar: 1.2, allergens: [.nuts])
        let banana = food("Banana", serving: 1, unit: .piece, kcal: 105, protein: 1.3, carbs: 27, fat: 0.4, fiber: 3.1, sugar: 14.4)
        foods = [oats, yogurt, strawberries, chicken, rice, avocado, almonds, banana]

        // MARK: Today's food log (breakfast, lunch, snack; dinner not yet logged)

        func entry(_ food: Food, _ quantity: Double, _ meal: MealType, _ date: Date) -> FoodLogEntry {
            FoodLogEntry(userID: userID, food: food, quantity: quantity, mealType: meal, loggedAt: date)
        }
        foodLog = [
            entry(oats, 80, .breakfast, at(8, 5)),
            entry(yogurt, 170, .breakfast, at(8, 5)),
            entry(strawberries, 100, .breakfast, at(8, 5)),
            entry(chicken, 150, .lunch, at(12, 45)),
            entry(rice, 200, .lunch, at(12, 45)),
            entry(avocado, 50, .lunch, at(12, 45)),
            entry(almonds, 28, .snack, at(16, 10)),
            entry(banana, 1, .snack, at(16, 10)),
        ]

        // MARK: Drinks and hydration (about 1.7 L of 2.3 L counted today)

        let water = DrinkPreset.water.drink(name: "Water")
        let flatWhite = DrinkPreset.flatWhite.drink(name: "Flat white")
        let greenTea = DrinkPreset.tea.drink(name: "Green tea")
        let cola = DrinkPreset.softDrink.drink(name: "Cola")
        drinks = [water, flatWhite, greenTea, cola]

        hydrationLog = [
            water.log(userID: userID, volumeMilliliters: 500, at: at(7, 40)),
            // 240 ml at 79% counts as about 190 ml.
            flatWhite.log(userID: userID, volumeMilliliters: 240, at: at(8, 10)),
            water.log(userID: userID, volumeMilliliters: 500, at: at(12, 30)),
            // 250 ml at 90% counts as 225 ml.
            greenTea.log(userID: userID, volumeMilliliters: 250, at: at(14, 20)),
            water.log(userID: userID, volumeMilliliters: 250, at: at(16, 30)),
            // Yesterday. Must not count toward today's progress.
            water.log(userID: userID, volumeMilliliters: 750, at: at(19, 0, dayOffset: -1)),
        ]

        // MARK: Workouts

        func exercise(_ name: String, sets: Int, reps: Int, kg: Double?) -> Exercise {
            Exercise(id: UUID(), name: name, sets: sets, reps: reps, weightKilograms: kg, durationSeconds: nil, notes: nil)
        }
        workouts = [
            Workout(
                id: UUID(),
                name: "Upper Body",
                type: .strength,
                durationMinutes: 50,
                exercises: [
                    exercise("Bench press", sets: 4, reps: 8, kg: 60),
                    exercise("Pull-up", sets: 4, reps: 8, kg: nil),
                    exercise("Overhead press", sets: 3, reps: 10, kg: 35),
                    exercise("Seated cable row", sets: 3, reps: 12, kg: 50),
                ],
                scheduledDate: at(18, 0),
                completedAt: nil,
                notes: nil,
                templateID: nil
            ),
            Workout(
                id: UUID(),
                name: "Easy run",
                type: .running,
                durationMinutes: 35,
                exercises: [],
                scheduledDate: at(7, 0, dayOffset: -2),
                completedAt: at(7, 40, dayOffset: -2),
                notes: "Zone 2, felt good.",
                templateID: nil
            ),
        ]

        // MARK: Inventory

        func item(
            _ name: String,
            _ quantity: Double,
            _ unit: QuantityUnit,
            expiresIn days: Int?,
            _ category: InventoryCategory,
            _ location: StorageLocation
        ) -> InventoryItem {
            InventoryItem(
                id: UUID(),
                name: name,
                quantity: quantity,
                unit: unit,
                purchaseDate: day(-2),
                expirationDate: days.map(day),
                category: category,
                location: location,
                notes: nil,
                status: .available,
                reminderSnoozedUntil: nil
            )
        }
        inventory = [
            item("Strawberries", 250, .gram, expiresIn: 1, .fruit, .fridge),
            item("Chicken breast", 500, .gram, expiresIn: 2, .protein, .fridge),
            item("Avocado", 2, .piece, expiresIn: 3, .fruit, .pantry),
            item("Greek yogurt", 2, .pack, expiresIn: 6, .dairy, .fridge),
            item("Jasmine rice", 1, .kilogram, expiresIn: 240, .carbohydrates, .pantry),
            item("Frozen spinach", 450, .gram, expiresIn: nil, .vegetables, .freezer),
        ]

        // MARK: Supplements (the user's own choices)

        let vitaminD = Supplement(
            id: UUID(), name: "Vitamin D", dosage: 1000, unit: .internationalUnit,
            schedule: .daily, reminderTime: DateComponents(hour: 8, minute: 0),
            reminderEnabled: true, notes: nil
        )
        let creatine = Supplement(
            id: UUID(), name: "Creatine", dosage: 5, unit: .gram,
            schedule: .daily, reminderTime: nil, reminderEnabled: false, notes: "With breakfast"
        )
        let omega3 = Supplement(
            id: UUID(), name: "Omega 3", dosage: 1, unit: .capsule,
            schedule: .weekdays([.monday, .wednesday, .friday]), reminderTime: nil,
            reminderEnabled: false, notes: nil
        )
        supplements = [vitaminD, creatine, omega3]
        supplementLog = [
            SupplementLog(id: UUID(), userID: userID, supplementID: vitaminD.id, takenAt: at(8, 10), dosage: 1000, unit: .internationalUnit),
            SupplementLog(id: UUID(), userID: userID, supplementID: creatine.id, takenAt: at(8, 10), dosage: 5, unit: .gram),
        ]

        // MARK: Weight history (weekly)

        weightHistory = zip([-21, -14, -7, 0], [67.2, 67.5, 67.8, 68.0]).map { offset, kg in
            WeightEntry(id: UUID(), userID: userID, weightKilograms: kg, measuredAt: at(7, 30, dayOffset: offset), source: .manual)
        }

        // MARK: Insights
        // Hand-written stand-ins for what the Phase 6 rules engine will produce.

        insights = [
            Insight(
                id: UUID(),
                ruleID: "nutrition.protein_target_streak",
                title: "Protein on track",
                body: "You reached your protein target 5 days this week.",
                severity: .positive,
                category: .nutrition,
                dataSource: .rule,
                createdAt: at(6, 0),
                expiresAt: day(1)
            ),
            Insight(
                id: UUID(),
                ruleID: "food.expiring_soon",
                title: "Use soon",
                body: "Strawberries expire tomorrow and chicken breast the day after.",
                severity: .attention,
                category: .food,
                dataSource: .rule,
                createdAt: at(6, 0),
                expiresAt: day(1)
            ),
        ]
    }
}
#endif
