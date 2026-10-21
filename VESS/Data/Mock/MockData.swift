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
    /// C01's pantry, beyond `inventory`: what Plan and recipes draw on.
    let pantryExtras: [InventoryItem]
    /// DATA.md: tonight's dinner is planned (miso-glazed cod, 19:30).
    let plannedMeals: [PlannedMeal]
    let supplements: [Supplement]
    let supplementLog: [SupplementLog]
    let weightHistory: [WeightEntry]
    let insights: [Insight]

    static let preview = MockData(now: AppClock.now, calendar: .current)

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

        // MARK: Workouts (DATA.md: Sunday's run recorded; cycle and strength entered)

        func exercise(_ name: String, sets: Int, reps: Int, kg: Double?) -> Exercise {
            Exercise(id: UUID(), name: name, sets: sets, reps: reps, weightKilograms: kg, durationSeconds: nil, notes: nil)
        }
        let run = Workout(
            id: UUID(), name: "Run", type: .running, durationMinutes: 32, exercises: [],
            scheduledDate: nil, completedAt: at(9, 0, dayOffset: -2),
            notes: "5.2 km · recorded by Apple Health", templateID: nil,
            source: .recorded, startedAt: at(8, 28, dayOffset: -2),
            activeEnergyKilocalories: 368, distanceMeters: 5_200, deviceName: "Apple Watch"
        )
        workouts = [
            run,
            Workout(
                id: UUID(), name: "Cycle", type: .cycling, durationMinutes: 62, exercises: [],
                scheduledDate: nil, completedAt: at(15, 0, dayOffset: -2),
                notes: "Moderate · entered", templateID: nil,
                effort: .moderate, source: .entered, startedAt: at(13, 58, dayOffset: -2),
                activeEnergyKilocalories: WorkoutEnergy.estimate(type: .cycling, effort: .moderate, minutes: 62, weightKilograms: 78.4)
            ),
            Workout(
                id: UUID(), name: "Strength", type: .strength, durationMinutes: 45,
                exercises: [exercise("Squat", sets: 4, reps: 8, kg: 70)],
                scheduledDate: nil, completedAt: at(18, 30, dayOffset: -1),
                notes: "Hard · entered", templateID: nil,
                effort: .hard, source: .entered, startedAt: at(17, 45, dayOffset: -1),
                activeEnergyKilocalories: WorkoutEnergy.estimate(type: .strength, effort: .hard, minutes: 45, weightKilograms: 78.4)
            ),
        ]

        // MARK: Health (DEBUG demo only; the real app shows "—" until Apple Health is connected)

        let history = Self.healthHistory(today: today, calendar: calendar, run: run)
        health = HealthSnapshot(
            steps: 6420, stepsTarget: 8000, activeEnergyKilocalories: 412, updatedAt: at(16, 20),
            hourlySteps: history.steps, hourlyActiveEnergy: history.energy, workouts: [run],
            latestWeight: BodyMassSample(kilograms: 78.4, measuredAt: at(7, 30))
        )

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
        // Pescatarian and nut-free (DATA.md overrides).
        pantryExtras = [
            item("Baby spinach", 150, .gram, expiresIn: 1, .vegetables, .fridge),
            item("Bok choy", 2, .piece, expiresIn: 2, .vegetables, .fridge),
            item("Hummus", 200, .gram, expiresIn: 4, .protein, .fridge),
            item("Skyr", 300, .gram, expiresIn: 6, .dairy, .fridge),
            item("Carrots", 500, .gram, expiresIn: 8, .vegetables, .fridge),
            item("Mixed berries", 400, .gram, expiresIn: nil, .fruit, .freezer),
            item("Peas", 500, .gram, expiresIn: nil, .vegetables, .freezer),
            item("Rolled oats", 500, .gram, expiresIn: nil, .carbohydrates, .pantry),
            item("Red lentils", 400, .gram, expiresIn: nil, .carbohydrates, .pantry),
            item("Chickpeas", 2, .pack, expiresIn: nil, .protein, .pantry),
            item("White miso", 200, .gram, expiresIn: nil, .other, .pantry),
            item("Mirin", 250, .milliliter, expiresIn: nil, .other, .pantry),
            item("Olive oil", 500, .milliliter, expiresIn: nil, .other, .pantry),
            item("Rye crackers", 200, .gram, expiresIn: nil, .carbohydrates, .pantry),
            item("Onions", 3, .piece, expiresIn: nil, .vegetables, .other),
        ]

        // MARK: Plan

        let miso = MealSuggestions.Candidate(recipe: Self.recipes[0])
        plannedMeals = [PlannedMeal(candidate: miso, day: today, meal: .dinner, now: day(-1), calendar: calendar)]

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
nonisolated extension MockData {
    /// F03's scanned product, for `-demoBarcode` captures on the simulator
    /// (which has no camera). Never looked up online.
    static let barcodeDemo = Food(
        id: UUID(),
        name: "Skyr, natural",
        brand: "Nordic Dairy",
        barcode: "5760466112233",
        servingSize: 150,
        servingUnit: .gram,
        nutrition: NutritionFacts(calories: 95, proteinGrams: 17, carbohydrateGrams: 6, fatGrams: 0.3),
        ingredients: [],
        allergens: [.lactose],
        quality: nil,
        source: .barcodeScan,
        createdAt: AppClock.now,
        updatedAt: AppClock.now,
        servingOptions: [ServingOption(label: "1 pot", amount: 150)]
    )
}
nonisolated extension MockData {
    /// Demo recipes for the DEBUG-only recipe screens (08) and suggestions:
    /// the dishes in the Plan references, pescatarian and nut-free per
    /// DATA.md. Nutrition is given only where a reference shows it; the rest
    /// is left unreported rather than guessed. Ingredients without a
    /// reference amount have none.
    static let recipes: [Recipe] = {
        func ingredient(_ name: String, _ quantity: Double? = nil, _ unit: QuantityUnit? = nil) -> Recipe.Ingredient {
            Recipe.Ingredient(name: name, quantity: quantity, unit: unit)
        }
        func facts(_ kcal: Double, _ protein: Double? = nil, _ carbs: Double? = nil, _ fat: Double? = nil) -> NutritionFacts {
            var facts = NutritionFacts(calories: kcal, proteinGrams: protein ?? 0, carbohydrateGrams: carbs ?? 0, fatGrams: fat ?? 0)
            var unreported = Set<CoreNutrient>()
            if protein == nil { unreported.insert(.protein) }
            if carbs == nil { unreported.insert(.carbohydrates) }
            if fat == nil { unreported.insert(.fat) }
            facts.unreportedCoreNutrients = unreported.isEmpty ? nil : unreported
            return facts
        }
        return [
            // 08-recipe-detail.
            Recipe(
                id: "miso-cod", name: "Miso-glazed cod with greens", mealType: .dinner, minutes: 25, servings: 2,
                nutrition: facts(620, 42, 58, 21),
                ingredients: [
                    ingredient("Cod fillets", 300, .gram), ingredient("White miso", 2, .tablespoon),
                    ingredient("Mirin", 1, .tablespoon), ingredient("Honey", 1, .teaspoon), ingredient("Bok choy", 2, .piece),
                    ingredient("Baby spinach", 100, .gram), ingredient("Jasmine rice", 150, .gram),
                    ingredient("Spring onions", 2, .piece),
                ],
                steps: [
                    "Whisk miso, mirin and a teaspoon of honey. Brush over the cod and rest 10 minutes.",
                    "Start the rice. Halve the bok choy lengthways.",
                    "Grill the cod 8–9 minutes until it flakes and the glaze catches.",
                    "Wilt the spinach and bok choy in the pan juices. Serve over rice with spring onions.",
                ],
                diets: [.pescatarian], allergens: [.soy]
            ),
            // A03, with chicken swapped for cod (DATA.md).
            Recipe(
                id: "cod-spinach-potatoes", name: "Cod, spinach & potatoes", mealType: .dinner, minutes: 30, servings: 1,
                nutrition: facts(690, 46, 52, 30),
                ingredients: [ingredient("Cod fillets", 400, .gram), ingredient("Baby spinach", 150, .gram), ingredient("Baby potatoes", 500, .gram)],
                steps: [], diets: [.pescatarian], allergens: []
            ),
            // A04.
            Recipe(
                id: "salmon-rice-greens", name: "Salmon, rice & greens", mealType: .dinner, minutes: 25, servings: 1,
                nutrition: facts(640, 44, 58, 22),
                ingredients: [ingredient("Salmon fillet", 150, .gram), ingredient("Jasmine rice", 90, .gram), ingredient("Broccoli", 1, .piece)],
                steps: [], diets: [.pescatarian], allergens: []
            ),
            // A01 / A07, kcal only.
            Recipe(id: "salmon-grain-bowl", name: "Salmon grain bowl", mealType: .lunch, minutes: 20, servings: 1,
                   nutrition: facts(720), ingredients: [ingredient("Salmon fillet"), ingredient("Baby spinach")],
                   steps: [], diets: [.pescatarian], allergens: []),
            Recipe(id: "prawn-chickpea-curry", name: "Prawn & chickpea curry, rice", mealType: .dinner, minutes: 30, servings: 2,
                   nutrition: facts(620), ingredients: [ingredient("Prawns"), ingredient("Chickpeas"), ingredient("Jasmine rice"), ingredient("Baby spinach")],
                   steps: [], diets: [.pescatarian], allergens: []),
            Recipe(id: "fish-tacos", name: "Fish tacos, red cabbage slaw", mealType: .dinner, minutes: 25, servings: 2,
                   nutrition: facts(680), ingredients: [ingredient("White fish"), ingredient("Tortillas"), ingredient("Red cabbage"), ingredient("Limes")],
                   steps: [], diets: [.pescatarian], allergens: [.gluten]),
            Recipe(id: "tomato-pasta-beans", name: "Tomato pasta, white beans", mealType: .dinner, minutes: 20, servings: 2,
                   nutrition: facts(650), ingredients: [ingredient("Pasta"), ingredient("White beans"), ingredient("Tomatoes"), ingredient("Basil")],
                   steps: [], diets: [.vegetarian, .vegan], allergens: [.gluten]),
            Recipe(id: "overnight-oats", name: "Overnight oats, berries", mealType: .breakfast, minutes: 5, servings: 1,
                   nutrition: facts(420), ingredients: [ingredient("Rolled oats"), ingredient("Mixed berries"), ingredient("Skyr")],
                   steps: [], diets: [.vegetarian], allergens: [.gluten, .lactose]),
            Recipe(id: "eggs-on-rye", name: "Eggs on rye", mealType: .breakfast, minutes: 10, servings: 1,
                   nutrition: facts(430), ingredients: [ingredient("Eggs"), ingredient("Rye bread")],
                   steps: [], diets: [.vegetarian], allergens: [.eggs, .gluten]),
            Recipe(id: "hummus-wrap", name: "Hummus & veg wrap", mealType: .lunch, minutes: 10, servings: 1,
                   nutrition: facts(610), ingredients: [ingredient("Hummus"), ingredient("Tortillas"), ingredient("Carrots")],
                   steps: [], diets: [.vegetarian], allergens: [.gluten]),
            Recipe(id: "lentil-soup", name: "Red lentil soup, rye", mealType: .lunch, minutes: 30, servings: 2,
                   nutrition: facts(560), ingredients: [ingredient("Red lentils"), ingredient("Onions"), ingredient("Carrots"), ingredient("Rye crackers")],
                   steps: [], diets: [.vegetarian, .vegan], allergens: [.gluten]),
        ]
    }()
}

nonisolated extension MockData {
    /// 61 days of hourly steps and active energy. The last seven days are
    /// DATA.md's (7,840 · 5,210 · 8,930 · 11,240 · 4,380 · 9,120 · 6,420 by
    /// 16:20 today); the four Tuesdays before average 8,000. Earlier days
    /// follow a fixed weekly pattern, so the demo is the same on every run.
    static func healthHistory(today: Date, calendar: Calendar, run: Workout) -> (steps: [HourlyValue], energy: [HourlyValue]) {
        let lastWeek = [-6: 7_840.0, -5: 5_210, -4: 8_930, -3: 11_240, -2: 4_380, -1: 9_120]
        let tuesdays = [-7: 7_600.0, -14: 8_400, -21: 7_900, -28: 8_100]
        // Calendar weekday (1 = Sunday) to a usual day's steps.
        let usual: [Int: Double] = [1: 9_400, 2: 8_600, 3: 8_000, 4: 7_700, 5: 5_600, 6: 8_800, 7: 11_000]
        let wobble: [Double] = [0.97, 1.03, 0.99, 1.02, 0.96, 1.04, 1.0]
        // Share of a day's steps per hour, 07:00–20:00.
        let dayShape: [Double] = [2, 6, 4, 3, 5, 13, 5, 3, 4, 3, 9, 5, 3, 2]
        // Today up to 16:20: 07:00–16:00.
        let todayShape: [Double] = [2, 6, 4, 3, 5, 13, 5, 3, 4, 2]

        var steps: [HourlyValue] = []
        var energy: [HourlyValue] = []
        func spread(_ total: Double, shape: [Double], on day: Date, kcalPerStep: Double, extraEnergy: [Int: Double] = [:]) {
            let sum = shape.reduce(0, +)
            var values = shape.map { (total * $0 / sum).rounded() }
            var kcal = values.map { ($0 * kcalPerStep).rounded() }
            // Rounding leftovers go to the busiest hour, so totals stay exact.
            if let peak = shape.indices.max(by: { shape[$0] < shape[$1] }) {
                values[peak] += total - values.reduce(0, +)
                kcal[peak] += (total * kcalPerStep).rounded() - kcal.reduce(0, +)
            }
            for index in shape.indices {
                guard let hour = calendar.date(byAdding: .hour, value: 7 + index, to: day) else { continue }
                steps.append(HourlyValue(start: hour, value: values[index]))
                energy.append(HourlyValue(start: hour, value: kcal[index] + (extraEnergy[7 + index] ?? 0)))
            }
        }

        for offset in stride(from: -60, through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if offset == 0 {
                spread(6_420, shape: todayShape, on: day, kcalPerStep: 412.0 / 6_420)
                continue
            }
            let weekday = calendar.component(.weekday, from: day)
            let total = lastWeek[offset] ?? tuesdays[offset]
                ?? ((usual[weekday] ?? 8_000) * wobble[(-offset / 7) % wobble.count]).rounded()
            // Sunday's recorded run adds its 368 kcal in the 08:00 hour.
            let extra: [Int: Double] = offset == -2 ? [8: run.activeEnergyKilocalories ?? 0] : [:]
            spread(total, shape: dayShape, on: day, kcalPerStep: 0.05, extraEnergy: extra)
        }
        return (steps, energy)
    }
}

#endif
