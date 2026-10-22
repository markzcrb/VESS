import Foundation
import SwiftData
import Testing
@testable import VESS

@MainActor
@Suite("Cycle storage")
struct CycleStoreTests {
    private let calendar = TestClock.utc

    private func cycleDay(_ date: Date, _ flow: CycleFlow, symptoms: Set<CycleSymptom> = [], note: String? = nil) -> CycleDay {
        CycleDay(id: UUID(), day: date, flow: flow, symptoms: symptoms, note: note)
    }

    @Test("A store written by the previous build (no cycle entity) opens with its data, and takes cycle days")
    func opensPreviousStore() throws {
        let url = URL.temporaryDirectory.appending(path: "previous-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        // The previous build's schema: every entity except StoredCycleDay.
        let previous = Schema([
            StoredProfile.self, StoredFoodLogEntry.self, StoredHydrationLog.self, StoredFood.self,
            StoredInventoryItem.self, StoredPlannedMeal.self, StoredGroceryItem.self, StoredWorkout.self, StoredSupplement.self,
        ])
        let profile = MockData(now: .now, calendar: calendar).profile
        do {
            let container = try ModelContainer(for: previous, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            // A profile saved before the cycle flag existed.
            context.insert(StoredProfile(id: profile.id, payload: try JSONEncoder().encode(profile)))
            try context.save()
        }

        let store = try LocalStore.onDisk(at: url)
        #expect(store.profile?.id == profile.id)
        #expect(store.profile?.isCycleTrackingOn == false)
        #expect(store.cycleDays.isEmpty)

        let today = try TestClock.date(2026, 10, 6)
        try store.save(cycleDay(today, .medium), calendar: calendar)
        #expect(store.cycleDays.count == 1)
    }

    @Test("One record per day: saving a day again replaces it; an empty day is removed")
    func oneDay() throws {
        let store = try LocalStore.inMemory()
        let morning = try TestClock.date(2026, 10, 6, 8)
        let evening = try TestClock.date(2026, 10, 6, 21)

        try store.save(cycleDay(morning, .light), calendar: calendar)
        try store.save(cycleDay(evening, .heavy, symptoms: [.cramps]), calendar: calendar)
        #expect(store.cycleDays.count == 1)
        #expect(store.cycleDay(on: morning, calendar: calendar)?.flow == .heavy)
        #expect(store.cycleDay(on: morning, calendar: calendar)?.day == calendar.startOfDay(for: morning))

        let id = try #require(store.cycleDay(on: morning, calendar: calendar)?.id)
        try store.save(CycleDay(id: id, day: morning, flow: .none, symptoms: [], note: "  "), calendar: calendar)
        #expect(store.cycleDays.isEmpty)
    }

    @Test("Moving a day to another date replaces that date's record")
    func moveDay() throws {
        let store = try LocalStore.inMemory()
        let first = try TestClock.date(2026, 10, 1)
        let second = try TestClock.date(2026, 10, 2)
        var day = cycleDay(first, .medium)
        try store.save(day, calendar: calendar)
        try store.save(cycleDay(second, .light), calendar: calendar)

        day.day = second
        try store.save(day, calendar: calendar)
        #expect(store.cycleDays.map(\.id) == [day.id])
        #expect(store.cycleDay(on: second, calendar: calendar)?.flow == .medium)
    }

    @Test("Export includes cycle days; Delete all data removes them")
    func exportAndDelete() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 10, 6, 18)
        try store.saveProfile(MockData(now: now, calendar: calendar).profile)
        try store.save(cycleDay(now, .medium, symptoms: [.bloating], note: "Long day"), calendar: calendar)

        let export = try JSONSerialization.jsonObject(with: store.exportData(now: now)) as? [String: Any]
        let days = try #require(export?["cycleDays"] as? [[String: Any]])
        #expect(days.count == 1)
        #expect(days.first?["flow"] as? String == "medium")
        #expect(days.first?["note"] as? String == "Long day")

        try store.deleteAllData()
        #expect(store.cycleDays.isEmpty)
    }
}
