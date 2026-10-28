import Foundation
import Observation
import OSLog
import SwiftData

/// The app's on-device data store and the single source of truth for screens.
///
/// Writes go to SwiftData immediately, so logging works offline. Screens read
/// through this store and never touch SwiftData directly. A sync engine
/// (Phase 7+) will observe the same store.
///
/// Reads are synchronous on the main actor; the data is small and local.
@Observable
final class LocalStore {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: AppLog.subsystem, category: "LocalStore")

    /// The user's profile; `nil` until onboarding completes.
    private(set) var profile: UserProfile?

    /// Bumped on every write so views that read logs re-render.
    private var revision = 0

    // Not persisted yet: Insights arrive in Phase 6. Empty in production;
    // filled only by sample data.
    private(set) var insights: [Insight] = []

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        profile = loadProfile()
    }

    /// The on-disk store used by the app.
    static func live() throws -> LocalStore {
        LocalStore(container: try makeContainer(inMemory: false))
    }

    /// The on-disk store's container, for opening it off the main thread:
    /// the first open after an update migrates (about 3 s on a cold
    /// simulator), which used to freeze the launch.
    nonisolated static func liveContainer() throws -> ModelContainer {
        try makeContainer(inMemory: false)
    }

    /// An empty store that is discarded on exit. Used by previews and UI tests.
    static func inMemory() throws -> LocalStore {
        LocalStore(container: try makeContainer(inMemory: true))
    }

    /// A store in a file at `url`. Used by tests that open a store written
    /// by an earlier build.
    static func onDisk(at url: URL) throws -> LocalStore {
        LocalStore(container: try ModelContainer(for: schema, configurations: ModelConfiguration(url: url)))
    }

    /// Every entity. New entities are added at the end and are always
    /// additive, so stores from earlier builds open unchanged.
    nonisolated static var schema: Schema {
        Schema([
            StoredProfile.self, StoredFoodLogEntry.self, StoredHydrationLog.self, StoredFood.self,
            StoredInventoryItem.self, StoredPlannedMeal.self, StoredGroceryItem.self, StoredWorkout.self, StoredSupplement.self,
            StoredCycleDay.self, StoredHabit.self, StoredHabitCheck.self,
            StoredSupplementLog.self, StoredCoachMessage.self, StoredRecipe.self,
        ])
    }

    nonisolated private static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    // MARK: Profile

    func saveProfile(_ newProfile: UserProfile) throws {
        // Profiles from onboarding or earlier builds get their nutrition preferences here.
        var updated = UserProfile.migrated(newProfile)
        updated.updatedAt = .now
        let payload = try encoder.encode(updated)

        let id = updated.id
        if let existing = try context.fetch(FetchDescriptor<StoredProfile>(predicate: #Predicate { $0.id == id })).first {
            existing.payload = payload
        } else {
            context.insert(StoredProfile(id: id, payload: payload))
        }
        try save()
        profile = updated
    }

    private func loadProfile() -> UserProfile? {
        do {
            guard let record = try context.fetch(FetchDescriptor<StoredProfile>()).first else { return nil }
            return UserProfile.migrated(try decoder.decode(UserProfile.self, from: record.payload))
        } catch {
            logger.error("Loading profile failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Food log

    /// Entries logged in `[start, end)`, oldest first.
    func foodEntries(from start: Date, to end: Date) -> [FoodLogEntry] {
        _ = revision
        let descriptor = FetchDescriptor<StoredFoodLogEntry>(
            predicate: #Predicate { $0.loggedAt >= start && $0.loggedAt < end },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
        return fetchDecoded(descriptor, as: FoodLogEntry.self) { $0.payload }
    }

    func foodEntries(on day: Date, calendar: Calendar) -> [FoodLogEntry] {
        let (start, end) = Self.bounds(of: day, calendar: calendar)
        return foodEntries(from: start, to: end)
    }

    func add(_ entry: FoodLogEntry) throws {
        context.insert(StoredFoodLogEntry(id: entry.id, loggedAt: entry.loggedAt, payload: try encoder.encode(entry)))
        try save()
    }

    func deleteFoodEntry(id: UUID) throws {
        try context.delete(model: StoredFoodLogEntry.self, where: #Predicate { $0.id == id })
        try save()
    }

    /// Replaces a logged entry (after editing its portion, meal or time).
    func update(_ entry: FoodLogEntry) throws {
        let id = entry.id
        guard let record = try context.fetch(FetchDescriptor<StoredFoodLogEntry>(predicate: #Predicate { $0.id == id })).first else {
            throw LocalStoreError.notFound
        }
        record.loggedAt = entry.loggedAt
        record.payload = try encoder.encode(entry)
        try save()
    }

    // MARK: Foods

    /// Saves or updates a food, keeping its favorite flag.
    func save(_ food: Food) throws {
        let id = food.id
        let payload = try encoder.encode(food)
        let key = FoodSearch.searchKey(for: food)
        if let existing = try context.fetch(FetchDescriptor<StoredFood>(predicate: #Predicate { $0.id == id })).first {
            existing.searchKey = key
            existing.barcode = food.barcode
            existing.updatedAt = food.updatedAt
            existing.payload = payload
        } else {
            context.insert(StoredFood(id: id, searchKey: key, barcode: food.barcode, isFavorite: false, updatedAt: food.updatedAt, payload: payload))
        }
        try save()
    }

    /// Marks a food as a favorite (saving a catalog food on first use).
    func setFavorite(_ isFavorite: Bool, for food: Food) throws {
        let id = food.id
        if try context.fetch(FetchDescriptor<StoredFood>(predicate: #Predicate { $0.id == id })).first == nil {
            try save(food)
        }
        guard let record = try context.fetch(FetchDescriptor<StoredFood>(predicate: #Predicate { $0.id == id })).first else { return }
        record.isFavorite = isFavorite
        try save()
    }

    /// Foods saved on this device, newest first.
    func savedFoods() -> [Food] {
        _ = revision
        return fetchDecoded(FetchDescriptor<StoredFood>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]), as: Food.self) { $0.payload }
    }

    func favoriteFoodIDs() -> Set<UUID> {
        _ = revision
        do {
            return Set(try context.fetch(FetchDescriptor<StoredFood>(predicate: #Predicate { $0.isFavorite })).map(\.id))
        } catch {
            logger.error("Fetching favorites failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func favoriteFoods() -> [Food] {
        _ = revision
        let descriptor = FetchDescriptor<StoredFood>(predicate: #Predicate { $0.isFavorite }, sortBy: [SortDescriptor(\.searchKey)])
        return fetchDecoded(descriptor, as: Food.self) { $0.payload }
    }

    /// Foods the user created themselves.
    func customFoods() -> [Food] {
        savedFoods().filter { $0.source == .userCreated }
    }

    /// A food by ID: saved foods first, then the starter catalog.
    func food(id: UUID) -> Food? {
        _ = revision
        let descriptor = FetchDescriptor<StoredFood>(predicate: #Predicate { $0.id == id })
        return fetchDecoded(descriptor, as: Food.self) { $0.payload }.first ?? StarterCatalog.food(id: id)
    }

    /// A saved food with this barcode, if any.
    func food(barcode: String) -> Food? {
        _ = revision
        let descriptor = FetchDescriptor<StoredFood>(predicate: #Predicate { $0.barcode == barcode })
        return fetchDecoded(descriptor, as: Food.self) { $0.payload }.first
    }

    /// Foods logged recently, most recent first, without duplicates.
    /// Quick-add entries have no food and are not included.
    func recentFoods(limit: Int = 20, now: Date = .now) -> [Food] {
        let start = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        let entries = foodEntries(from: start, to: now.addingTimeInterval(60))
        var seen = Set<UUID>()
        var foods: [Food] = []
        for entry in entries.reversed() {
            guard let id = entry.foodID, seen.insert(id).inserted, let food = food(id: id) else { continue }
            foods.append(food)
            if foods.count == limit { break }
        }
        return foods
    }

    /// Local search across saved foods and the starter catalog. Never touches the network.
    func searchLocalFoods(_ query: String) -> [Food] {
        FoodSearch.results(for: query, in: savedFoods() + StarterCatalog.foods, favorites: favoriteFoodIDs())
    }

    // MARK: Hydration

    func hydrationLogs(from start: Date, to end: Date) -> [HydrationLog] {
        _ = revision
        let descriptor = FetchDescriptor<StoredHydrationLog>(
            predicate: #Predicate { $0.loggedAt >= start && $0.loggedAt < end },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
        return fetchDecoded(descriptor, as: HydrationLog.self) { $0.payload }
    }

    func hydrationLogs(on day: Date, calendar: Calendar) -> [HydrationLog] {
        let (start, end) = Self.bounds(of: day, calendar: calendar)
        return hydrationLogs(from: start, to: end)
    }

    func add(_ log: HydrationLog) throws {
        context.insert(StoredHydrationLog(id: log.id, loggedAt: log.loggedAt, payload: try encoder.encode(log)))
        try save()
    }

    /// Replaces a logged drink (after editing its amount or time).
    func update(_ log: HydrationLog) throws {
        let id = log.id
        guard let record = try context.fetch(FetchDescriptor<StoredHydrationLog>(predicate: #Predicate { $0.id == id })).first else {
            throw LocalStoreError.notFound
        }
        record.loggedAt = log.loggedAt
        record.payload = try encoder.encode(log)
        try save()
    }

    func deleteHydrationLog(id: UUID) throws {
        try context.delete(model: StoredHydrationLog.self, where: #Predicate { $0.id == id })
        try save()
    }

    // MARK: Pantry

    /// What's at home now (status available), soonest expiry first, then by name.
    var inventory: [InventoryItem] {
        _ = revision
        let descriptor = FetchDescriptor<StoredInventoryItem>(predicate: #Predicate { $0.isActive })
        return fetchDecoded(descriptor, as: InventoryItem.self) { $0.payload }
            .sorted(by: PantryOverview.soonestFirst)
    }

    func inventoryItem(id: UUID) -> InventoryItem? {
        _ = revision
        let descriptor = FetchDescriptor<StoredInventoryItem>(predicate: #Predicate { $0.id == id })
        return fetchDecoded(descriptor, as: InventoryItem.self) { $0.payload }.first
    }

    /// Adds or updates an item. Used up or thrown away items leave the
    /// pantry but are kept.
    func save(_ item: InventoryItem) throws {
        let payload = try encoder.encode(item)
        let id = item.id
        let isActive = item.status == .available
        if let existing = try context.fetch(FetchDescriptor<StoredInventoryItem>(predicate: #Predicate { $0.id == id })).first {
            existing.expirationDate = item.expirationDate
            existing.isActive = isActive
            existing.payload = payload
        } else {
            context.insert(StoredInventoryItem(id: id, expirationDate: item.expirationDate, isActive: isActive, payload: payload))
        }
        try save()
    }

    func deleteInventoryItem(id: UUID) throws {
        try context.delete(model: StoredInventoryItem.self, where: #Predicate { $0.id == id })
        try save()
    }

    // MARK: Plan

    /// Meals planned from `start` (inclusive) to `end` (exclusive), by day.
    func plannedMeals(from start: Date, to end: Date) -> [PlannedMeal] {
        _ = revision
        let descriptor = FetchDescriptor<StoredPlannedMeal>(
            predicate: #Predicate { $0.day >= start && $0.day < end },
            sortBy: [SortDescriptor(\.day)]
        )
        return fetchDecoded(descriptor, as: PlannedMeal.self) { $0.payload }
    }

    func plannedMeal(id: UUID) -> PlannedMeal? {
        _ = revision
        let descriptor = FetchDescriptor<StoredPlannedMeal>(predicate: #Predicate { $0.id == id })
        return fetchDecoded(descriptor, as: PlannedMeal.self) { $0.payload }.first
    }

    /// Adds or updates a planned meal.
    func save(_ meal: PlannedMeal) throws {
        let payload = try encoder.encode(meal)
        let id = meal.id
        if let existing = try context.fetch(FetchDescriptor<StoredPlannedMeal>(predicate: #Predicate { $0.id == id })).first {
            existing.day = meal.day
            existing.payload = payload
        } else {
            context.insert(StoredPlannedMeal(id: id, day: meal.day, payload: payload))
        }
        try save()
    }

    func deletePlannedMeal(id: UUID) throws {
        try context.delete(model: StoredPlannedMeal.self, where: #Predicate { $0.id == id })
        try save()
    }

    // MARK: Grocery

    /// Items the user added and changes made to plan lines.
    var groceryItems: [GroceryItem] {
        _ = revision
        return fetchDecoded(FetchDescriptor<StoredGroceryItem>(), as: GroceryItem.self) { $0.payload }
    }

    func save(_ item: GroceryItem) throws {
        let payload = try encoder.encode(item)
        let id = item.id
        if let existing = try context.fetch(FetchDescriptor<StoredGroceryItem>(predicate: #Predicate { $0.id == id })).first {
            existing.payload = payload
        } else {
            context.insert(StoredGroceryItem(id: id, payload: payload))
        }
        try save()
    }

    func deleteGroceryItem(id: UUID) throws {
        try context.delete(model: StoredGroceryItem.self, where: #Predicate { $0.id == id })
        try save()
    }

    // MARK: Workouts

    /// Workouts the user entered, newest first. Recorded workouts come from
    /// Apple Health through `HealthDataStore` and are never stored here.
    var workouts: [Workout] {
        _ = revision
        let descriptor = FetchDescriptor<StoredWorkout>(sortBy: [SortDescriptor(\.completedAt, order: .reverse)])
        return fetchDecoded(descriptor, as: Workout.self) { $0.payload }
    }

    func workout(id: UUID) -> Workout? {
        _ = revision
        let descriptor = FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == id })
        return fetchDecoded(descriptor, as: Workout.self) { $0.payload }.first
    }

    /// Adds or updates an entered workout.
    func save(_ workout: Workout) throws {
        let payload = try encoder.encode(workout)
        let id = workout.id
        let completedAt = workout.completedAt ?? .now
        if let existing = try context.fetch(FetchDescriptor<StoredWorkout>(predicate: #Predicate { $0.id == id })).first {
            existing.completedAt = completedAt
            existing.payload = payload
        } else {
            context.insert(StoredWorkout(id: id, completedAt: completedAt, payload: payload))
        }
        try save()
    }

    func deleteWorkout(id: UUID) throws {
        try context.delete(model: StoredWorkout.self, where: #Predicate { $0.id == id })
        try save()
    }

    // MARK: Supplements

    /// The user's supplements, by name.
    var supplements: [Supplement] {
        _ = revision
        return fetchDecoded(FetchDescriptor<StoredSupplement>(), as: Supplement.self) { $0.payload }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func save(_ supplement: Supplement) throws {
        let payload = try encoder.encode(supplement)
        let id = supplement.id
        if let existing = try context.fetch(FetchDescriptor<StoredSupplement>(predicate: #Predicate { $0.id == id })).first {
            existing.payload = payload
        } else {
            context.insert(StoredSupplement(id: id, payload: payload))
        }
        try save()
    }

    /// Removes a supplement and the record of taking it.
    func deleteSupplement(id: UUID) throws {
        try context.delete(model: StoredSupplement.self, where: #Predicate { $0.id == id })
        try context.delete(model: StoredSupplementLog.self, where: #Predicate { $0.supplementID == id })
        try save()
    }

    /// Supplements taken on `day`.
    func supplementLogs(on day: Date, calendar: Calendar) -> [SupplementLog] {
        _ = revision
        let (start, end) = Self.bounds(of: day, calendar: calendar)
        let descriptor = FetchDescriptor<StoredSupplementLog>(predicate: #Predicate { $0.takenAt >= start && $0.takenAt < end })
        return fetchDecoded(descriptor, as: SupplementLog.self) { $0.payload }
    }

    func add(_ log: SupplementLog) throws {
        context.insert(StoredSupplementLog(id: log.id, supplementID: log.supplementID, takenAt: log.takenAt, payload: try encoder.encode(log)))
        try save()
    }

    func deleteSupplementLog(id: UUID) throws {
        try context.delete(model: StoredSupplementLog.self, where: #Predicate { $0.id == id })
        try save()
    }

    // MARK: Cycle

    /// Every logged cycle day, oldest first. Kept when cycle tracking is
    /// turned off, so turning it back on restores the history.
    var cycleDays: [CycleDay] {
        _ = revision
        return fetchDecoded(FetchDescriptor<StoredCycleDay>(sortBy: [SortDescriptor(\.day)]), as: CycleDay.self) { $0.payload }
    }

    func cycleDay(on day: Date, calendar: Calendar) -> CycleDay? {
        let (start, end) = Self.bounds(of: day, calendar: calendar)
        let descriptor = FetchDescriptor<StoredCycleDay>(predicate: #Predicate { $0.day >= start && $0.day < end })
        _ = revision
        return fetchDecoded(descriptor, as: CycleDay.self) { $0.payload }.first
    }

    /// Saves the day, replacing whatever was logged for that calendar day.
    /// An empty day (no flow, symptoms or note) is removed instead.
    func save(_ cycleDay: CycleDay, calendar: Calendar) throws {
        var value = cycleDay
        value.day = calendar.startOfDay(for: cycleDay.day)
        let (start, end) = Self.bounds(of: value.day, calendar: calendar)
        let id = value.id
        try context.delete(model: StoredCycleDay.self, where: #Predicate { ($0.day >= start && $0.day < end) || $0.id == id })
        if !value.isEmpty {
            context.insert(StoredCycleDay(id: value.id, day: value.day, payload: try encoder.encode(value)))
        }
        try save()
    }

    func deleteCycleDay(id: UUID) throws {
        try context.delete(model: StoredCycleDay.self, where: #Predicate { $0.id == id })
        try save()
    }

    /// Every cycle day, when tracking is switched off with "Delete cycle data".
    func deleteCycleData() throws {
        try context.delete(model: StoredCycleDay.self)
        try save()
    }

    // MARK: Habits

    /// The user's habits, in the order they were added.
    var habits: [Habit] {
        _ = revision
        return fetchDecoded(FetchDescriptor<StoredHabit>(sortBy: [SortDescriptor(\.createdAt)]), as: Habit.self) { $0.payload }
    }

    /// Adds or updates a habit.
    func save(_ habit: Habit) throws {
        let payload = try encoder.encode(habit)
        let id = habit.id
        if let existing = try context.fetch(FetchDescriptor<StoredHabit>(predicate: #Predicate { $0.id == id })).first {
            existing.payload = payload
        } else {
            context.insert(StoredHabit(id: id, createdAt: habit.createdAt, payload: payload))
        }
        try save()
    }

    /// Removes a habit and its ticks.
    func deleteHabit(id: UUID) throws {
        try context.delete(model: StoredHabit.self, where: #Predicate { $0.id == id })
        try context.delete(model: StoredHabitCheck.self, where: #Predicate { $0.habitID == id })
        try save()
    }

    /// Ticks from `start` (inclusive) to `end` (exclusive).
    func habitChecks(from start: Date, to end: Date) -> [HabitCheck] {
        _ = revision
        let descriptor = FetchDescriptor<StoredHabitCheck>(predicate: #Predicate { $0.day >= start && $0.day < end })
        return fetchDecoded(descriptor, as: HabitCheck.self) { $0.payload }
    }

    /// One more tick for a "2× a day" habit.
    func addHabitCheck(_ habitID: UUID, on day: Date, calendar: Calendar) throws {
        let (start, _) = Self.bounds(of: day, calendar: calendar)
        let check = HabitCheck(id: UUID(), habitID: habitID, day: start)
        context.insert(StoredHabitCheck(id: check.id, habitID: habitID, day: start, payload: try encoder.encode(check)))
        try save()
    }

    /// Ticks or unticks a habit for a day: one tick, or none.
    func setHabit(_ habitID: UUID, done: Bool, on day: Date, calendar: Calendar) throws {
        let (start, end) = Self.bounds(of: day, calendar: calendar)
        try context.delete(model: StoredHabitCheck.self, where: #Predicate { $0.habitID == habitID && $0.day >= start && $0.day < end })
        if done {
            let check = HabitCheck(id: UUID(), habitID: habitID, day: start)
            context.insert(StoredHabitCheck(id: check.id, habitID: habitID, day: start, payload: try encoder.encode(check)))
        }
        try save()
    }

    // MARK: Coach

    /// The conversation, oldest first.
    var coachMessages: [CoachMessage] {
        _ = revision
        return fetchDecoded(FetchDescriptor<StoredCoachMessage>(sortBy: [SortDescriptor(\.createdAt)]), as: CoachMessage.self) { $0.payload }
    }

    func add(_ message: CoachMessage) throws {
        context.insert(StoredCoachMessage(id: message.id, createdAt: message.createdAt, payload: try encoder.encode(message)))
        try save()
    }

    /// "Clear conversation".
    func deleteCoachMessages() throws {
        try context.delete(model: StoredCoachMessage.self)
        try save()
    }

    // MARK: Recipes

    /// The user's own and saved AI recipes, newest first.
    var userRecipes: [Recipe] {
        _ = revision
        return fetchDecoded(FetchDescriptor<StoredRecipe>(), as: Recipe.self) { $0.payload }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func recipePhoto(id: String) -> Data? {
        _ = revision
        return try? context.fetch(FetchDescriptor<StoredRecipe>(predicate: #Predicate { $0.id == id })).first?.photo
    }

    /// Adds or replaces a user or AI recipe. `photo` replaces the stored
    /// one; `nil` keeps it unless `removePhoto`.
    func save(_ recipe: Recipe, photo: Data? = nil, removePhoto: Bool = false) throws {
        precondition(recipe.origin != .discover, "Discover recipes are bundled, not stored")
        let id = recipe.id
        let payload = try encoder.encode(recipe)
        if let existing = try context.fetch(FetchDescriptor<StoredRecipe>(predicate: #Predicate { $0.id == id })).first {
            existing.payload = payload
            existing.updatedAt = .now
            if let photo { existing.photo = photo } else if removePhoto { existing.photo = nil }
        } else {
            context.insert(StoredRecipe(id: id, updatedAt: .now, payload: payload, photo: photo))
        }
        try save()
    }

    func deleteRecipe(id: String) throws {
        try context.delete(model: StoredRecipe.self, where: #Predicate { $0.id == id })
        try save()
    }

    /// For every recipe logged at least once: how often, and when last.
    var cookedRecipes: [String: (count: Int, last: Date)] {
        _ = revision
        var result: [String: (count: Int, last: Date)] = [:]
        for entry in fetchDecoded(FetchDescriptor<StoredFoodLogEntry>(), as: FoodLogEntry.self, payload: { $0.payload }) {
            guard let id = entry.recipeID else { continue }
            let current = result[id]
            result[id] = ((current?.count ?? 0) + 1, max(current?.last ?? .distantPast, entry.loggedAt))
        }
        return result
    }

    /// How often a recipe was logged ("Cooked 3×"). A recipe logs as one
    /// entry, so this counts entries.
    func cookedCount(recipeID: String) -> Int {
        _ = revision
        return fetchDecoded(FetchDescriptor<StoredFoodLogEntry>(), as: FoodLogEntry.self) { $0.payload }
            .count { $0.recipeID == recipeID }
    }

    // MARK: Export

    /// Everything VESS stores on this iPhone, as one JSON document (E07).
    /// Dates are ISO 8601. Apple Health data isn't included: VESS doesn't
    /// store it.
    func exportData(now: Date) throws -> Data {
        _ = revision
        let document = ExportDocument(
            app: "UMEVA",
            exportedAt: now,
            profile: profile,
            foodLog: fetchDecoded(FetchDescriptor<StoredFoodLogEntry>(), as: FoodLogEntry.self) { $0.payload }
                .sorted { $0.loggedAt < $1.loggedAt },
            drinks: fetchDecoded(FetchDescriptor<StoredHydrationLog>(), as: HydrationLog.self) { $0.payload },
            savedFoods: fetchDecoded(FetchDescriptor<StoredFood>(), as: Food.self) { $0.payload },
            pantry: fetchDecoded(FetchDescriptor<StoredInventoryItem>(), as: InventoryItem.self) { $0.payload },
            plannedMeals: fetchDecoded(FetchDescriptor<StoredPlannedMeal>(), as: PlannedMeal.self) { $0.payload },
            grocery: groceryItems,
            workouts: workouts,
            supplements: supplements,
            supplementLog: fetchDecoded(FetchDescriptor<StoredSupplementLog>(sortBy: [SortDescriptor(\.takenAt)]), as: SupplementLog.self) { $0.payload },
            cycleDays: cycleDays,
            habits: habits,
            habitChecks: fetchDecoded(FetchDescriptor<StoredHabitCheck>(sortBy: [SortDescriptor(\.day)]), as: HabitCheck.self) { $0.payload },
            coachMessages: coachMessages,
            recipes: userRecipes
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private struct ExportDocument: Encodable {
        let app: String
        let exportedAt: Date
        let profile: UserProfile?
        let foodLog: [FoodLogEntry]
        let drinks: [HydrationLog]
        let savedFoods: [Food]
        let pantry: [InventoryItem]
        let plannedMeals: [PlannedMeal]
        let grocery: [GroceryItem]
        let workouts: [Workout]
        let supplements: [Supplement]
        let supplementLog: [SupplementLog]
        /// Cycle tracking, if it was ever used.
        let cycleDays: [CycleDay]
        let habits: [Habit]
        let habitChecks: [HabitCheck]
        /// The Coach conversation, kept only here.
        let coachMessages: [CoachMessage]
        /// The user's own and saved AI recipes (photos left out).
        let recipes: [Recipe]
    }

    // MARK: Account data

    /// Deletes everything stored on this device and returns to onboarding.
    func deleteAllData() throws {
        try context.delete(model: StoredProfile.self)
        try context.delete(model: StoredFoodLogEntry.self)
        try context.delete(model: StoredHydrationLog.self)
        try context.delete(model: StoredFood.self)
        try context.delete(model: StoredInventoryItem.self)
        try context.delete(model: StoredPlannedMeal.self)
        try context.delete(model: StoredGroceryItem.self)
        try context.delete(model: StoredWorkout.self)
        try context.delete(model: StoredSupplement.self)
        try context.delete(model: StoredSupplementLog.self)
        try context.delete(model: StoredCoachMessage.self)
        try context.delete(model: StoredCycleDay.self)
        try context.delete(model: StoredHabit.self)
        try context.delete(model: StoredHabitCheck.self)
        try context.delete(model: StoredRecipe.self)
        try save()
        profile = nil
        insights = []
    }

    // MARK: Helpers

    private func save() throws {
        do {
            try context.save()
            revision += 1
        } catch {
            context.rollback()
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func fetchDecoded<Record: PersistentModel, Value: Decodable>(
        _ descriptor: FetchDescriptor<Record>,
        as type: Value.Type,
        payload: (Record) -> Data
    ) -> [Value] {
        do {
            return try context.fetch(descriptor).compactMap { record in
                do {
                    return try decoder.decode(type, from: payload(record))
                } catch {
                    // Skip a corrupt record rather than losing the whole day.
                    logger.error("Decoding \(String(describing: type), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        } catch {
            logger.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    enum LocalStoreError: Error {
        case notFound
    }

    static func bounds(of day: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }
}

#if DEBUG
extension LocalStore {
    /// Fills the store with sample data. Debug builds only: previews, tests,
    /// and the `-seedSampleData` launch argument.
    func seed(_ data: MockData) throws {
        try saveProfile(data.profile)
        // The sample log refers to these foods, so Recent can resolve them.
        for food in data.foods { try save(food) }
        for entry in data.foodHistory + data.foodLog { try add(entry) }
        for log in data.hydrationLog { try add(log) }
        for workout in data.workouts where !workout.isRecorded { try save(workout) }
        for supplement in data.supplements { try save(supplement) }
        for log in data.supplementLog { try add(log) }
        for item in data.inventory + data.pantryExtras { try save(item) }
        for meal in data.plannedMeals { try save(meal) }
        insights = data.insights
    }

    enum PreviewContent {
        /// Sample profile and a full day of logs.
        case sampleDay
        /// Sample profile, nothing logged: the first-day empty state.
        case profileOnly
        /// No profile: onboarding.
        case empty
    }

    /// An in-memory store for previews.
    static func preview(_ content: PreviewContent = .sampleDay) -> LocalStore {
        do {
            let store = try inMemory()
            switch content {
            case .sampleDay: try store.seed(.preview)
            case .profileOnly: try store.saveProfile(MockData.preview.profile)
            case .empty: break
            }
            return store
        } catch {
            fatalError("Preview store failed: \(error)")
        }
    }
}
#endif
