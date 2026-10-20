import Foundation
import Testing
@testable import VESS

@Suite("Pantry")
struct PantryTests {
    private func item(_ name: String, expiresIn days: Int?, _ location: StorageLocation, now: Date, status: InventoryStatus = .available) -> InventoryItem {
        InventoryItem(
            id: UUID(), name: name, quantity: 1, unit: .piece, purchaseDate: nil,
            expirationDate: days.flatMap { TestClock.utc.date(byAdding: .day, value: $0, to: now) },
            category: .other, location: location, notes: nil, status: status, reminderSnoozedUntil: nil
        )
    }

    @Test("Use soon holds items within three days, soonest first; the rest group by location")
    func overview() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let items = [
            item("Rice", expiresIn: nil, .pantry, now: now),
            item("Bok choy", expiresIn: 2, .fridge, now: now),
            item("Hummus", expiresIn: 4, .fridge, now: now),
            item("Spinach", expiresIn: 1, .fridge, now: now),
            item("Old milk", expiresIn: -1, .fridge, now: now),
            item("Peas", expiresIn: nil, .freezer, now: now),
            item("Eaten", expiresIn: 1, .fridge, now: now, status: .consumed),
        ]
        let overview = PantryOverview(items: items, now: now, calendar: TestClock.utc)

        #expect(overview.useSoon.map(\.name) == ["Old milk", "Spinach", "Bok choy"])
        #expect(overview.groups.map(\.location) == [.fridge, .freezer, .pantry])
        #expect(overview.groups.first?.items.map(\.name) == ["Hummus"])
        #expect(overview.totalCount == 6, "Used-up items are not at home")
    }

    @Test("Expiry presets set the start of a day and are recognised again")
    func presets() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let calendar = TestClock.utc
        let week = try #require(ExpiryPreset.inAWeek.date(from: now, calendar: calendar))
        #expect(week == (try TestClock.date(2026, 10, 13, 0, 0)))
        #expect(ExpiryPreset.matching(week, now: now, calendar: calendar) == .inAWeek)
        #expect(ExpiryPreset.matching(nil, now: now, calendar: calendar) == .noDate)
        #expect(ExpiryPreset.matching(try TestClock.date(2026, 10, 11), now: now, calendar: calendar) == nil)
    }

    @MainActor
    @Test("Pantry items persist; used up or thrown away items leave the pantry")
    func persistence() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        var spinach = item("Spinach", expiresIn: 1, .fridge, now: now)
        let rice = item("Rice", expiresIn: nil, .pantry, now: now)
        try store.save(spinach)
        try store.save(rice)
        #expect(store.inventory.map(\.name) == ["Spinach", "Rice"])

        spinach.quantity = 2
        try store.save(spinach)
        #expect(store.inventoryItem(id: spinach.id)?.quantity == 2)

        spinach.status = .discarded
        try store.save(spinach)
        #expect(store.inventory.map(\.name) == ["Rice"])
        #expect(store.inventoryItem(id: spinach.id)?.status == .discarded, "Kept for food-waste insights")

        try store.deleteInventoryItem(id: rice.id)
        #expect(store.inventory.isEmpty)
    }
}
