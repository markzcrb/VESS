import Foundation
import SwiftData
import Testing
@testable import VESS

@MainActor
@Suite("Habit storage")
struct HabitStoreTests {
    private let calendar = TestClock.utc

    private func habit(_ name: String = "Vitamin D") throws -> Habit {
        Habit(id: UUID(), name: name, schedule: .daily, category: .supplements,
              reminder: DateComponents(hour: 8, minute: 0), auto: nil, createdAt: try TestClock.date(2026, 10, 1))
    }

    @Test("A store from the previous build (cycle days, no habits) opens with its data, and takes habits")
    func opensPreviousStore() throws {
        let url = URL.temporaryDirectory.appending(path: "previous-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let previous = Schema([
            StoredProfile.self, StoredFoodLogEntry.self, StoredHydrationLog.self, StoredFood.self,
            StoredInventoryItem.self, StoredPlannedMeal.self, StoredGroceryItem.self, StoredWorkout.self, StoredSupplement.self,
            StoredCycleDay.self,
        ])
        let profile = MockData(now: .now, calendar: calendar).profile
        let cycleDay = CycleDay(id: UUID(), day: try TestClock.date(2026, 10, 1), flow: .medium, symptoms: [], note: nil)
        do {
            let context = ModelContext(try ModelContainer(for: previous, configurations: ModelConfiguration(url: url)))
            context.insert(StoredProfile(id: profile.id, payload: try JSONEncoder().encode(profile)))
            context.insert(StoredCycleDay(id: cycleDay.id, day: cycleDay.day, payload: try JSONEncoder().encode(cycleDay)))
            try context.save()
        }

        let store = try LocalStore.onDisk(at: url)
        #expect(store.profile?.id == profile.id)
        #expect(store.cycleDays.map(\.id) == [cycleDay.id])
        #expect(store.habits.isEmpty)
        try store.save(try habit())
        #expect(store.habits.count == 1)
    }

    @Test("Habits save and update in order; one tick per day; deleting a habit removes its ticks")
    func habitsAndTicks() throws {
        let store = try LocalStore.inMemory()
        var first = try habit("Vitamin D")
        let second = try habit("Walk after lunch")
        try store.save(first)
        try store.save(second)
        first.name = "Vitamin D3"
        try store.save(first)
        #expect(store.habits.map(\.name).sorted() == ["Vitamin D3", "Walk after lunch"])

        let day = try TestClock.date(2026, 10, 6, 9)
        let (start, end) = LocalStore.bounds(of: day, calendar: calendar)
        try store.setHabit(first.id, done: true, on: day, calendar: calendar)
        try store.setHabit(first.id, done: true, on: try TestClock.date(2026, 10, 6, 21), calendar: calendar)
        try store.setHabit(second.id, done: true, on: day, calendar: calendar)
        #expect(store.habitChecks(from: start, to: end).count == 2)

        try store.setHabit(second.id, done: false, on: day, calendar: calendar)
        #expect(store.habitChecks(from: start, to: end).map(\.habitID) == [first.id])

        try store.deleteHabit(id: first.id)
        #expect(store.habits.map(\.id) == [second.id])
        #expect(store.habitChecks(from: start, to: end).isEmpty)
    }

    @Test("Export includes habits and ticks; Delete all data removes them")
    func exportAndDelete() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 10, 6, 18)
        try store.saveProfile(MockData(now: now, calendar: calendar).profile)
        let item = try habit()
        try store.save(item)
        try store.setHabit(item.id, done: true, on: now, calendar: calendar)

        let export = try JSONSerialization.jsonObject(with: store.exportData(now: now)) as? [String: Any]
        #expect((export?["habits"] as? [[String: Any]])?.first?["name"] as? String == "Vitamin D")
        #expect((export?["habitChecks"] as? [[String: Any]])?.count == 1)

        try store.deleteAllData()
        #expect(store.habits.isEmpty)
        let (start, end) = LocalStore.bounds(of: now, calendar: calendar)
        #expect(store.habitChecks(from: start, to: end).isEmpty)
    }
}
