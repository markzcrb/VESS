import Foundation
import Testing
@testable import VESS

@Suite("Meal reminders")
struct MealRemindersTests {
    private let calendar = TestClock.utc
    private let userID = UUID()

    private func entry(_ meal: MealType, at date: Date) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID(), userID: userID, foodID: nil, foodName: "Food", mealType: meal,
            quantity: 1, servingUnit: .serving,
            nutrition: NutritionFacts(calories: 400, proteinGrams: 20, carbohydrateGrams: 40, fatGrams: 15),
            loggedAt: date
        )
    }

    /// Breakfast 07:30, lunch 12:30, dinner 21:45 on the three days before 6 Oct.
    private func history() throws -> [FoodLogEntry] {
        try (3...5).flatMap { day in
            [
                entry(.breakfast, at: try TestClock.date(2026, 10, day, 7, 30)),
                entry(.lunch, at: try TestClock.date(2026, 10, day, 12, 30)),
                entry(.dinner, at: try TestClock.date(2026, 10, day, 21, 45)),
            ]
        }
    }

    @Test("30 minutes after the usual time, only for unlogged meals, never in quiet hours")
    func plan() throws {
        let now = try TestClock.date(2026, 10, 6, 10, 0)
        let logged = [entry(.breakfast, at: try TestClock.date(2026, 10, 6, 7, 40))]
        let plan = MealReminders.plan(history: try history(), logged: logged, now: now, calendar: calendar, days: 2)

        #expect(plan.map(\.id) == ["meal.lunch.2026-10-06", "meal.breakfast.2026-10-07", "meal.lunch.2026-10-07"],
                "Breakfast is logged today; dinner's 22:15 is in quiet hours")
        let lunch = try TestClock.date(2026, 10, 6, 13, 0)
        #expect(plan.first?.date == lunch)
    }

    @Test("Past times and meals without three days of history get no reminder")
    func pastAndUnknown() throws {
        let now = try TestClock.date(2026, 10, 6, 14, 0)
        let short = Array(try history().prefix(6))
        let plan = MealReminders.plan(history: short, logged: [], now: now, calendar: calendar, days: 1)
        #expect(plan.isEmpty, "Lunch's 13:00 has passed; two days of history isn't enough")
    }

    @Test("Quiet hours are 22:00 to 07:00")
    func quiet() throws {
        let ten = try TestClock.date(2026, 10, 6, 22, 0)
        let beforeSeven = try TestClock.date(2026, 10, 6, 6, 59)
        let seven = try TestClock.date(2026, 10, 6, 7, 0)
        let beforeTen = try TestClock.date(2026, 10, 6, 21, 59)
        #expect(MealReminders.isQuiet(ten, calendar: calendar))
        #expect(MealReminders.isQuiet(beforeSeven, calendar: calendar))
        #expect(!MealReminders.isQuiet(seven, calendar: calendar))
        #expect(!MealReminders.isQuiet(beforeTen, calendar: calendar))
    }
}

@MainActor
@Suite("You data")
struct YouDataTests {
    @Test("Supplements are saved, sorted by name and deleted")
    func supplements() throws {
        let store = try LocalStore.inMemory()
        let omega = Supplement(id: UUID(), name: "Omega 3", dosage: 1, unit: .capsule, schedule: .daily, reminderTime: nil, reminderEnabled: false, notes: nil)
        let magnesium = Supplement(id: UUID(), name: "Magnesium", dosage: 200, unit: .milligram, schedule: .daily,
                                   reminderTime: DateComponents(hour: 21, minute: 0), reminderEnabled: true, notes: nil)
        try store.save(omega)
        try store.save(magnesium)
        #expect(store.supplements.map(\.name) == ["Magnesium", "Omega 3"])
        try store.deleteSupplement(id: omega.id)
        #expect(store.supplements.map(\.name) == ["Magnesium"])
    }

    @Test("Export is one JSON document with every kind of stored data and ISO 8601 dates")
    func export() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let data = MockData(now: now, calendar: TestClock.utc)
        try store.seed(data)
        let json = try store.exportData(now: now)
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])

        for key in ["profile", "foodLog", "drinks", "savedFoods", "pantry", "plannedMeals", "grocery", "workouts", "supplements"] {
            #expect(object[key] != nil, "\(key)")
        }
        let foodLog = object["foodLog"] as? [Any]
        let supplements = object["supplements"] as? [Any]
        #expect(foodLog?.isEmpty == false)
        #expect(supplements?.count == data.supplements.count)
        #expect(object["exportedAt"] as? String == "2026-10-06T18:40:00Z")
    }

    @Test("Profiles saved before the steps goal still decode, with 8,000 steps")
    func oldProfile() throws {
        let profile = MockData(now: .now, calendar: .current).profile
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        json.removeValue(forKey: "stepsTarget")
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.stepsTarget == nil)
        #expect(decoded.dailyStepsTarget == 8_000)
    }
}

@Suite("Unit plurals")
struct UnitPluralTests {
    @Test("Countable units take a plural from the string catalog; measured units don't")
    func plurals() {
        #expect(QuantityUnit.piece.amountText(1) == "1 piece")
        #expect(QuantityUnit.piece.amountText(2) == "2 pieces")
        #expect(QuantityUnit.slice.amountText(1.5).hasSuffix("slices"))
        #expect(QuantityUnit.pack.amountText(3) == "3 packs")
        #expect(QuantityUnit.gram.amountText(150) == "150 g")
        #expect(SupplementUnit.capsule.amountText(1) == "1 capsule")
        #expect(SupplementUnit.tablet.amountText(2) == "2 tablets")
    }
}
