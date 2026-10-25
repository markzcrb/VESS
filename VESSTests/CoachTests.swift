import Foundation
import SwiftData
import Testing
@testable import VESS

@MainActor
@Suite("Coach")
struct CoachTests {
    private let calendar = TestClock.utc
    private let userID = UUID()

    private func entry(_ name: String, _ meal: MealType, kcal: Double, protein: Double = 20, at date: Date) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID(), userID: userID, foodID: nil, foodName: name, mealType: meal,
            quantity: 1, servingUnit: .serving,
            nutrition: NutritionFacts(calories: kcal, proteinGrams: protein, carbohydrateGrams: 30, fatGrams: 10),
            loggedAt: date
        )
    }

    private func water(_ ml: Double, at date: Date) -> HydrationLog {
        HydrationLog(id: UUID(), userID: userID, drinkID: nil, drinkName: "Water", drinkType: .water,
                     volumeMilliliters: ml, hydrationContributionPercent: 100, calories: 0, sugarGrams: 0,
                     caffeineMilligrams: 0, loggedAt: date)
    }

    private func input(now: Date, entries: [FoodLogEntry] = [], drinks: [HydrationLog] = [], steps: [HourlyValue]? = nil,
                       cycle: CoachContextInput.CycleShare? = nil, workouts: [Workout] = []) -> CoachContextInput {
        CoachContextInput(
            now: now, calendar: calendar, name: "Mark",
            targets: NutritionTargets(calories: 2400, proteinGrams: 140, carbohydrateGrams: 280, fatGrams: 80),
            waterTargetMilliliters: 2200, stepsTarget: 9000,
            entries: entries, drinks: drinks, hourlySteps: steps,
            habitsDone: ["Walk after lunch"], habitsOpen: ["Stretch"],
            workouts: workouts, supplementsTaken: ["Vitamin D"], supplementsDue: ["Creatine"], cycle: cycle
        )
    }

    @Test("Today's totals, meals in order, and the 7 days before today averaged over days with meals")
    func totals() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let entries = [
            entry("Oats", .breakfast, kcal: 400, protein: 15, at: try TestClock.date(2026, 10, 6, 7, 45)),
            entry("Poke bowl", .lunch, kcal: 690, protein: 40, at: try TestClock.date(2026, 10, 6, 12, 30)),
            entry("Later", .dinner, kcal: 900, at: try TestClock.date(2026, 10, 6, 20)),     // after now: left out
            entry("Mon", .lunch, kcal: 2000, protein: 120, at: try TestClock.date(2026, 10, 5, 12)),
            entry("Sat", .lunch, kcal: 1800, protein: 100, at: try TestClock.date(2026, 10, 3, 12)),
            entry("Too old", .lunch, kcal: 5000, at: try TestClock.date(2026, 9, 28, 12)),
        ]
        let drinks = [water(500, at: try TestClock.date(2026, 10, 6, 9)), water(1000, at: try TestClock.date(2026, 10, 5, 9))]
        let context = CoachContextBuilder.build(input(now: now, entries: entries, drinks: drinks))

        #expect(context.date == "2026-10-06" && context.time == "18:40" && context.name == "Mark")
        #expect(context.today.kcal == 1090 && context.today.proteinG == 55 && context.today.waterMl == 500)
        #expect(context.today.steps == nil, "No Apple Health: no steps, not zero")
        #expect(context.mealsToday.map(\.name) == ["Oats", "Poke bowl"])
        #expect(context.last7Days.daysLogged == 2)
        #expect(context.last7Days.avgKcal == 1900 && context.last7Days.avgProteinG == 110)
        #expect(context.last7Days.avgWaterMl == 1000)
        #expect(context.targets.kcal == 2400 && context.targets.steps == 9000)
        #expect(context.habitsToday.done == ["Walk after lunch"] && context.supplementsToday.open == ["Creatine"])
    }

    @Test("Cycle is in the summary only when the caller passes it (tracking and sharing both on)")
    func cycleGate() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        #expect(CoachContextBuilder.build(input(now: now)).cycle == nil)
        let window = DateInterval(start: try TestClock.date(2026, 10, 20), end: try TestClock.date(2026, 10, 23))
        let shared = CoachContextBuilder.build(input(now: now, cycle: .init(cycleDay: 12, nextPeriod: window)))
        #expect(shared.cycle?.cycleDay == 12 && shared.cycle?.nextPeriodFrom == "2026-10-20" && shared.cycle?.nextPeriodTo == "2026-10-23")
        let json = String(decoding: CoachContextBuilder.json(CoachContextBuilder.build(input(now: now))), as: UTF8.self)
        #expect(!json.contains("cycle"), "No cycle key at all when not shared")
    }

    @Test("\"pregnant\": true only when Pregnant is on in You › Body; no key otherwise")
    func pregnant() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let off = String(decoding: CoachContextBuilder.json(CoachContextBuilder.build(input(now: now))), as: UTF8.self)
        #expect(!off.contains("pregnant"))
        var on = input(now: now)
        on.pregnant = true
        let json = String(decoding: CoachContextBuilder.json(CoachContextBuilder.build(on)), as: UTF8.self)
        #expect(json.contains("\"pregnant\":true"))
    }

    @Test("snake_case JSON, under 6 KB even with a very long day")
    func sizeCap() throws {
        let now = try TestClock.date(2026, 10, 6, 23)
        let many = (0..<120).map { i in
            entry(String(repeating: "Long food name \(i) ", count: 4), .snack, kcal: 50, at: now.addingTimeInterval(Double(-i * 60)))
        }
        let workouts = (0..<40).map { i in
            Workout(id: UUID(), name: "Walk", type: .walking, durationMinutes: 30, exercises: [], scheduledDate: nil,
                    completedAt: now.addingTimeInterval(Double(-i * 3600)), notes: nil, templateID: nil)
        }
        let context = CoachContextBuilder.build(input(now: now, entries: many, workouts: workouts))
        let json = CoachContextBuilder.json(context)
        #expect(json.count <= CoachContextBuilder.maxBytes)
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.contains("\"last_7_days\"") && text.contains("\"protein_g\"") && text.contains("\"meals_today\""))
        #expect(context.today.kcal == 6000, "Totals are kept even when the list is cut")
    }

    @Test("The request: last 20 messages, starting and ending with a question, with context and locale")
    func requestBody() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        var history: [CoachMessage] = []
        for i in 0..<25 {
            history.append(CoachMessage(id: UUID(), role: i.isMultiple(of: 2) ? .user : .assistant, text: "m\(i)", createdAt: now))
        }
        let trimmed = CoachRequest.messages(history)
        #expect(trimmed.count <= 20 && trimmed.first?.role == .user && trimmed.last?.role == .user)
        #expect(trimmed.last?.text == "m24")

        let body = CoachRequest.body(history: history, context: CoachContextBuilder.build(input(now: now)), locale: "en")
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((object["messages"] as? [[String: String]])?.count == trimmed.count)
        #expect(object["locale"] as? String == "en")
        let context = try #require(object["context"] as? [String: Any])
        #expect(context["targets"] != nil && context["last_7_days"] != nil)
    }

    @Test("Replies decode with and without remaining")
    func replyDecoding() throws {
        let reply = try JSONDecoder().decode(CoachReply.self, from: Data(#"{"reply":"Hi","remaining":17}"#.utf8))
        #expect(reply == CoachReply(reply: "Hi", remaining: 17))
        #expect(try JSONDecoder().decode(CoachReply.self, from: Data(#"{"reply":"Hi"}"#.utf8)).remaining == nil)
    }

    @Test("The conversation is stored here, in order; Clear removes it; export and Delete all include it")
    func storage() throws {
        let store = try LocalStore.inMemory()
        let t = try TestClock.date(2026, 10, 6, 18)
        try store.add(CoachMessage(id: UUID(), role: .user, text: "Q", createdAt: t))
        try store.add(CoachMessage(id: UUID(), role: .assistant, text: "A", createdAt: t.addingTimeInterval(5)))
        #expect(store.coachMessages.map(\.text) == ["Q", "A"])
        let export = try JSONSerialization.jsonObject(with: store.exportData(now: t)) as? [String: Any]
        #expect((export?["coachMessages"] as? [Any])?.count == 2)
        try store.deleteCoachMessages()
        #expect(store.coachMessages.isEmpty)
        try store.add(CoachMessage(id: UUID(), role: .user, text: "Q", createdAt: t))
        try store.deleteAllData()
        #expect(store.coachMessages.isEmpty)
    }

    @Test("A store from the previous build (no Coach entity) opens and takes messages")
    func opensPreviousStore() throws {
        let url = URL.temporaryDirectory.appending(path: "previous-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let previous = Schema([
            StoredProfile.self, StoredFoodLogEntry.self, StoredHydrationLog.self, StoredFood.self,
            StoredInventoryItem.self, StoredPlannedMeal.self, StoredGroceryItem.self, StoredWorkout.self, StoredSupplement.self,
            StoredCycleDay.self, StoredHabit.self, StoredHabitCheck.self, StoredSupplementLog.self,
        ])
        let profile = MockData(now: .now, calendar: calendar).profile
        do {
            let context = ModelContext(try ModelContainer(for: previous, configurations: ModelConfiguration(url: url)))
            context.insert(StoredProfile(id: profile.id, payload: try JSONEncoder().encode(profile)))
            try context.save()
        }
        let store = try LocalStore.onDisk(at: url)
        #expect(store.profile?.id == profile.id && store.coachMessages.isEmpty)
        try store.add(CoachMessage(id: UUID(), role: .user, text: "Hello", createdAt: .now))
        #expect(store.coachMessages.count == 1)
    }

    @Test("The server's usage day is UTC")
    func serverDay() throws {
        // 00:30 in Bratislava (UTC+2) is still the day before in UTC.
        var bratislava = Calendar(identifier: .gregorian)
        bratislava.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        let date = try #require(bratislava.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 0, minute: 30)))
        #expect(CoachView.serverDay(date) == "2026-10-06")
    }
}
