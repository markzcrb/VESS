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
    /// The six days before today, for usual meal times and regularity.
    let foodHistory: [FoodLogEntry]
    let health: HealthSnapshot
    /// I09 "Full day": the estimated dinner (585 kcal), bringing today to
    /// 2,425 kcal.
    let fullDayExtras: [FoodLogEntry]
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

        // MARK: Profile (Redesign/docs/DATA.md: Mark, maintaining, pescatarian, nut-free)

        profile = UserProfile(
            id: userID,
            name: "Mark",
            dateOfBirth: calendar.date(byAdding: .year, value: -29, to: today),
            sex: .male,
            heightCentimeters: 180,
            weightKilograms: 78.4,
            goalWeightKilograms: nil,
            goal: .maintainWeight,
            activityLevel: .moderate,
            dietaryPreference: .custom,
            customDietDescription: "Pescatarian",
            allergies: [.nuts],
            otherRestrictions: [],
            focusAreas: [.nutrition, .hydration, .mealPlanning],
            nutritionTargets: NutritionTargets(
                calories: 2400,
                proteinGrams: 140,
                carbohydrateGrams: 260,
                fatGrams: 80
            ),
            waterTargetMilliliters: 2200,
            createdAt: day(-84),
            updatedAt: day(-1)
        )

        // MARK: Foods (values per serving, which is also the logged portion)

        func food(
            _ name: String,
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
                brand: nil,
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

        // Breakfast 674 kcal, lunch 894 kcal, snack 272 kcal: 1,840 kcal, 108 g
        // protein, 196 g carbs, 58 g fat and 21 g fibre (DATA.md).
        let yogurt = food("Greek yogurt", serving: 260, unit: .gram, kcal: 189, protein: 23, carbs: 9, fat: 6, sugar: 9, allergens: [.lactose], processing: .processed)
        let oats = food("Oats", serving: 95, unit: .gram, kcal: 369, protein: 12, carbs: 54, fat: 8, fiber: 7.5, sugar: 1, allergens: [.gluten])
        let blueberries = food("Blueberries", serving: 200, unit: .gram, kcal: 116, protein: 1, carbs: 23, fat: 1, fiber: 3.5, sugar: 19)
        let salmonPoke = food("Salmon poke", serving: 155, unit: .gram, kcal: 324, protein: 31, carbs: 0, fat: 24)
        let edamame = food("Edamame", serving: 105, unit: .gram, kcal: 126, protein: 11, carbs: 8, fat: 6, fiber: 4, allergens: [.soy])
        let brownRice = food("Brown rice", serving: 325, unit: .gram, kcal: 444, protein: 8, carbs: 77, fat: 4, fiber: 4)
        let skyr = food("Skyr", serving: 195, unit: .gram, kcal: 123, protein: 18, carbs: 7, fat: 0.5, sugar: 7, allergens: [.lactose], processing: .processed)
        let pumpkinSeeds = food("Pumpkin seeds", serving: 13, unit: .gram, kcal: 73, protein: 3.7, carbs: 2, fat: 8.2, fiber: 0.6)
        let apple = food("Apple", serving: 1, unit: .piece, kcal: 76, protein: 0.3, carbs: 16, fat: 0.3, fiber: 1.4, sugar: 12)
        foods = [yogurt, oats, blueberries, salmonPoke, edamame, brownRice, skyr, pumpkinSeeds, apple]

        // MARK: Today's food log (breakfast, lunch, snack; dinner not yet logged)

        func entry(_ food: Food, _ meal: MealType, _ date: Date) -> FoodLogEntry {
            FoodLogEntry(userID: userID, food: food, quantity: food.servingSize, mealType: meal, loggedAt: date)
        }
        foodLog = [
            entry(yogurt, .breakfast, at(7, 45)),
            entry(oats, .breakfast, at(7, 45)),
            entry(blueberries, .breakfast, at(7, 45)),
            entry(salmonPoke, .lunch, at(12, 30)),
            entry(edamame, .lunch, at(12, 30)),
            entry(brownRice, .lunch, at(12, 30)),
            entry(skyr, .snack, at(16, 10)),
            entry(pumpkinSeeds, .snack, at(16, 10)),
            entry(apple, .snack, at(16, 10)),
        ]

        // I09: the estimated dinner brings today to 2,425 kcal and 147 g protein.
        let dinner = food("Baked salmon, jasmine rice, roasted greens", serving: 1, unit: .serving, kcal: 585, protein: 39, carbs: 57, fat: 21, fiber: 5)
        fullDayExtras = [entry(dinner, .dinner, at(18, 40))]

        // MARK: Prior 12 days (DATA.md's week, twice), for usual meal times and trends

        let weekEnergy: [Double] = [2310, 2480, 1960, 2520, 2390, 2180]
        let weekProtein: [Double] = [122, 138, 96, 144, 131, 118]
        let dailyEnergy = weekEnergy + weekEnergy
        let dailyProtein = weekProtein + weekProtein
        let slots: [(MealType, Int, Int, Double)] = [
            (.breakfast, 7, 45, 0.25), (.lunch, 12, 30, 0.35), (.snack, 16, 10, 0.10), (.dinner, 19, 30, 0.30),
        ]
        foodHistory = dailyEnergy.indices.flatMap { index -> [FoodLogEntry] in
            let offset = index - dailyEnergy.count
            // A few minutes either side of the usual time, so medians are realistic.
            let jitter = [-10, 5, 0, 10, -5, 15][index % 6]
            return slots.map { meal, hour, minute, share in
                // DATA.md gives energy and protein; carbs and fat follow the
                // target split (43 % and 30 % of energy).
                var nutrition = NutritionFacts(
                    calories: dailyEnergy[index] * share,
                    proteinGrams: dailyProtein[index] * share,
                    carbohydrateGrams: dailyEnergy[index] * share * 0.43 / 4,
                    fatGrams: dailyEnergy[index] * share * 0.30 / 9
                )
                nutrition.fiberGrams = 24 * share
                return FoodLogEntry(
                    id: UUID(), userID: userID, foodID: nil, foodName: meal.rawValue.capitalized,
                    mealType: meal, quantity: 1, servingUnit: .serving,
                    nutrition: nutrition,
                    loggedAt: at(hour, minute, dayOffset: offset).addingTimeInterval(Double(jitter * 60))
                )
            }
        }

        // MARK: Drinks and hydration (1.6 L of 2.2 L counted today)

        let water = DrinkPreset.water.drink(name: "Water")
        let sparkling = DrinkPreset.sparklingWater.drink(name: "Sparkling water")
        let greenTea = DrinkPreset.tea.drink(name: "Green tea")
        drinks = [water, sparkling, greenTea]

        var hydrationLog = [
            water.log(userID: userID, volumeMilliliters: 500, at: at(10, 15)),
            sparkling.log(userID: userID, volumeMilliliters: 330, at: at(13, 0)),
            // 300 ml at 90% counts as 270 ml.
            greenTea.log(userID: userID, volumeMilliliters: 300, at: at(15, 40)),
            water.log(userID: userID, volumeMilliliters: 500, at: at(17, 20)),
        ]
        // Prior 12 days: 2 L a day in four glasses. Never today, so today's
        // progress stays exactly the four drinks above.
        hydrationLog += (1...12).flatMap { offset in
            [9, 13, 17, 20].map { hour in
                water.log(userID: userID, volumeMilliliters: 500, at: at(hour, 0, dayOffset: -offset))
            }
        }

        self.hydrationLog = hydrationLog

        // MARK: Health (DEBUG demo only; the real app shows "—" until Apple Health is connected)

        health = HealthSnapshot(steps: 6420, stepsTarget: 8000, activeEnergyKilocalories: 412, updatedAt: at(16, 20))

        // MARK: Workouts

        func exercise(_ name: String, sets: Int, reps: Int, kg: Double?) -> Exercise {
            Exercise(id: UUID(), name: name, sets: sets, reps: reps, weightKilograms: kg, durationSeconds: nil, notes: nil)
        }
        workouts = [
            Workout(
                id: UUID(), name: "Run", type: .running, durationMinutes: 32, exercises: [],
                scheduledDate: nil, completedAt: at(9, 0, dayOffset: -2),
                notes: "5.2 km · recorded by Apple Health", templateID: nil
            ),
            Workout(
                id: UUID(), name: "Cycle", type: .cycling, durationMinutes: 62, exercises: [],
                scheduledDate: nil, completedAt: at(15, 0, dayOffset: -2),
                notes: "Moderate · entered", templateID: nil
            ),
            Workout(
                id: UUID(), name: "Strength", type: .strength, durationMinutes: 45,
                exercises: [exercise("Squat", sets: 4, reps: 8, kg: 70)],
                scheduledDate: nil, completedAt: at(18, 30, dayOffset: -1),
                notes: "Hard · entered", templateID: nil
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
            item("Cod fillets", 400, .gram, expiresIn: 2, .protein, .fridge),
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

        weightHistory = zip([-84, -56, -28, 0], [79.0, 78.8, 78.6, 78.4]).map { offset, kg in
            WeightEntry(id: UUID(), userID: userID, weightKilograms: kg, measuredAt: at(7, 30, dayOffset: offset), source: .manual)
        }

        // MARK: Insights
        // Hand-written stand-ins for what the Phase 6 rules engine will produce.

        insights = [
            Insight(
                id: UUID(),
                ruleID: "nutrition.protein_target_streak",
                title: "Protein on track",
                body: "You reached your protein target 3 of the last 6 days.",
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
                body: "Strawberries expire tomorrow and the cod fillets the day after.",
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
