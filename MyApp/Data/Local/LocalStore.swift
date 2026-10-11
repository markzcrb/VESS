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
    private let logger = Logger(subsystem: "VESS", category: "LocalStore")

    /// The user's profile; `nil` until onboarding completes.
    private(set) var profile: UserProfile?

    /// Bumped on every write so views that read logs re-render.
    private var revision = 0

    // Not persisted yet: these arrive with Activity (Phase 4), Plan (Phase 5)
    // and Insights (Phase 6). Empty in production; filled only by sample data.
    private(set) var workouts: [Workout] = []
    private(set) var inventory: [InventoryItem] = []
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

    /// An empty store that is discarded on exit. Used by previews and UI tests.
    static func inMemory() throws -> LocalStore {
        LocalStore(container: try makeContainer(inMemory: true))
    }

    private static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([StoredProfile.self, StoredFoodLogEntry.self, StoredHydrationLog.self, StoredFood.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }

    // MARK: Profile

    func saveProfile(_ newProfile: UserProfile) throws {
        var updated = newProfile
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
            return try decoder.decode(UserProfile.self, from: record.payload)
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

    func deleteHydrationLog(id: UUID) throws {
        try context.delete(model: StoredHydrationLog.self, where: #Predicate { $0.id == id })
        try save()
    }

    // MARK: Account data

    /// Deletes everything stored on this device and returns to onboarding.
    func deleteAllData() throws {
        try context.delete(model: StoredProfile.self)
        try context.delete(model: StoredFoodLogEntry.self)
        try context.delete(model: StoredHydrationLog.self)
        try context.delete(model: StoredFood.self)
        try save()
        profile = nil
        workouts = []
        inventory = []
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
        for entry in data.foodLog { try add(entry) }
        for log in data.hydrationLog { try add(log) }
        workouts = data.workouts
        inventory = data.inventory
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
