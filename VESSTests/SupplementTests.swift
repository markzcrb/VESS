import Foundation
import SwiftData
import Testing
@testable import VESS

@MainActor
@Suite("Supplements")
struct SupplementTests {
    private let calendar = TestClock.utc
    private let userID = UUID()

    private func supplement(_ name: String, _ schedule: SupplementSchedule = .daily, time: SupplementTimeOfDay? = nil, category: SupplementCategory? = nil) -> Supplement {
        Supplement(id: UUID(), name: name, dosage: 1, unit: .capsule, schedule: schedule,
                   reminderTime: nil, reminderEnabled: false, notes: nil, category: category, timeOfDay: time)
    }

    private func log(_ supplement: Supplement, at date: Date) -> SupplementLog {
        SupplementLog(id: UUID(), userID: userID, supplementID: supplement.id, takenAt: date, dosage: supplement.dosage, unit: supplement.unit)
    }

    @Test("Due today: daily, or on chosen weekdays; as-needed never is")
    func scheduled() throws {
        let tuesday = try TestClock.date(2026, 10, 6, 9)
        #expect(SupplementRules.isScheduled(supplement("D3"), on: tuesday, calendar: calendar))
        #expect(!SupplementRules.isScheduled(supplement("Omega-3", .weekdays([.monday, .wednesday])), on: tuesday, calendar: calendar))
        #expect(SupplementRules.isScheduled(supplement("Omega-3", .weekdays([.tuesday])), on: tuesday, calendar: calendar))
        #expect(!SupplementRules.isScheduled(supplement("Zinc", .asNeeded), on: tuesday, calendar: calendar))
    }

    @Test("Today: due ones plus anything taken; morning first; taken counts only what was due")
    func today() throws {
        let tuesday = try TestClock.date(2026, 10, 6, 18)
        let magnesium = supplement("Magnesium", time: .evening)
        let d3 = supplement("Vitamin D3", time: .morning)
        let zinc = supplement("Zinc", .asNeeded)
        let iron = supplement("Iron", .asNeeded)
        let logs = [
            log(d3, at: try TestClock.date(2026, 10, 6, 8, 10)),
            log(d3, at: try TestClock.date(2026, 10, 6, 9)),
            log(zinc, at: try TestClock.date(2026, 10, 6, 12)),
            log(magnesium, at: try TestClock.date(2026, 10, 5, 21)),   // yesterday
        ]
        let today = SupplementRules.today([magnesium, d3, zinc, iron], logs: logs, on: tuesday, calendar: calendar)
        #expect(today.items.map(\.supplement.name) == ["Vitamin D3", "Magnesium", "Zinc"], "Iron isn't due and wasn't taken")
        #expect(today.items.first?.takenAt == (try TestClock.date(2026, 10, 6, 8, 10)), "The first time it was taken")
        #expect(today.items[1].takenAt == nil, "Yesterday's doesn't count")
        #expect(today.dueCount == 2 && today.takenCount == 1)
    }

    @Test("Presets carry no dose; the user's own of the same name come first, matched loosely")
    func presets() {
        let mine = [supplement("omega 3", category: .omega3), supplement("Ashwagandha", category: .herbal)]
        let omega = SupplementRules.presets(in: .omega3, mine: mine)
        #expect(omega.first?.existing?.name == "omega 3")
        let vitamins = SupplementRules.presets(in: .vitamins, mine: mine).map(\.preset.name)
        #expect(vitamins == ["Vitamin D3", "Vitamin B12", "Multivitamin"])
        #expect(SupplementRules.presets.map(\.category).contains(.performance))
        #expect(SupplementRules.ownOnly(in: .herbal, mine: mine).map(\.name) == ["Ashwagandha"])
        let found = SupplementRules.search("vit", mine: mine)
        #expect(found.presets.map(\.name) == ["Vitamin D3", "Vitamin B12", "Multivitamin"])
        #expect(SupplementRules.search("OMEGA", mine: mine).presets.isEmpty, "The user's own is shown instead")
        #expect(SupplementRules.search("  ", mine: mine).presets.isEmpty)
    }

    @Test("Supplements saved before categories decode, with no category or time of day")
    func oldSupplement() throws {
        let json = #"{"id":"6A1B2C3D-0000-0000-0000-000000000001","name":"Vitamin D","dosage":1000,"unit":"internationalUnit","schedule":{"daily":{}},"reminderEnabled":false}"#
        let decoded = try JSONDecoder().decode(Supplement.self, from: Data(json.utf8))
        #expect(decoded.name == "Vitamin D" && decoded.category == nil && decoded.timeOfDay == nil)
    }

    @Test("A store from the previous build (habits, no supplement log) opens with its data, and takes logs")
    func opensPreviousStore() throws {
        let url = URL.temporaryDirectory.appending(path: "previous-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let previous = Schema([
            StoredProfile.self, StoredFoodLogEntry.self, StoredHydrationLog.self, StoredFood.self,
            StoredInventoryItem.self, StoredPlannedMeal.self, StoredGroceryItem.self, StoredWorkout.self, StoredSupplement.self,
            StoredCycleDay.self, StoredHabit.self, StoredHabitCheck.self,
        ])
        let d3 = supplement("Vitamin D3")
        do {
            let context = ModelContext(try ModelContainer(for: previous, configurations: ModelConfiguration(url: url)))
            context.insert(StoredSupplement(id: d3.id, payload: try JSONEncoder().encode(d3)))
            try context.save()
        }

        let store = try LocalStore.onDisk(at: url)
        #expect(store.supplements.map(\.id) == [d3.id])
        let day = try TestClock.date(2026, 10, 6, 8)
        try store.add(log(d3, at: day))
        #expect(store.supplementLogs(on: day, calendar: calendar).count == 1)
    }

    @Test("Logs are per day; deleting a supplement removes its logs; export and Delete all include them")
    func logs() throws {
        let store = try LocalStore.inMemory()
        let d3 = supplement("Vitamin D3")
        try store.save(d3)
        let today = try TestClock.date(2026, 10, 6, 8)
        let entry = log(d3, at: today)
        try store.add(entry)
        try store.add(log(d3, at: try TestClock.date(2026, 10, 5, 8)))
        #expect(store.supplementLogs(on: today, calendar: calendar).map(\.id) == [entry.id])

        let export = try JSONSerialization.jsonObject(with: store.exportData(now: today)) as? [String: Any]
        #expect((export?["supplementLog"] as? [Any])?.count == 2)

        try store.deleteSupplementLog(id: entry.id)
        #expect(store.supplementLogs(on: today, calendar: calendar).isEmpty)
        try store.deleteSupplement(id: d3.id)
        #expect(store.supplementLogs(on: try TestClock.date(2026, 10, 5, 8), calendar: calendar).isEmpty)

        try store.save(d3)
        try store.add(entry)
        try store.deleteAllData()
        #expect(store.supplementLogs(on: today, calendar: calendar).isEmpty)
    }
}

@Suite("Add sheet types")
struct AddTypeRulesTests {
    @Test("Carousel order; Photo and Cycle only when on, leaving no gap")
    func visible() {
        #expect(AddTypeRules.visible(photo: true, cycle: true) == AddType.allCases)
        #expect(AddTypeRules.visible(photo: false, cycle: false) == [.quickAdd, .food, .drink, .supplements, .workout, .habits, .weight])
    }

    @Test("Opens on the requested type, else the last one within an hour, else Food")
    func initial() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let shown = AddTypeRules.visible(photo: false, cycle: false)
        #expect(AddTypeRules.initial(requested: nil, lastUsed: nil, lastUsedAt: nil, now: now, visible: shown) == .food)
        #expect(AddTypeRules.initial(requested: .drink, lastUsed: .workout, lastUsedAt: now, now: now, visible: shown) == .drink)
        #expect(AddTypeRules.initial(requested: nil, lastUsed: .workout, lastUsedAt: now.addingTimeInterval(-3600), now: now, visible: shown) == .workout)
        #expect(AddTypeRules.initial(requested: nil, lastUsed: .workout, lastUsedAt: now.addingTimeInterval(-3601), now: now, visible: shown) == .food)
        #expect(AddTypeRules.initial(requested: nil, lastUsed: .cycle, lastUsedAt: now, now: now, visible: shown) == .food, "Cycle was turned off")
        #expect(AddTypeRules.initial(requested: .cycle, lastUsed: nil, lastUsedAt: nil, now: now, visible: shown) == .food)
    }
}
