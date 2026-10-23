import Foundation
import Testing
@testable import VESS

@Suite("Plan")
struct WeekPlanTests {
    private let calendar = TestClock.utc
    private let userID = UUID()

    private func entry(_ name: String, _ meal: MealType, at date: Date) -> FoodLogEntry {
        FoodLogEntry(
            id: UUID(), userID: userID, foodID: UUID(), foodName: name, mealType: meal,
            quantity: 1, servingUnit: .serving, nutrition: NutritionFacts(calories: 500, proteinGrams: 30, carbohydrateGrams: 50, fatGrams: 15),
            loggedAt: date
        )
    }

    private func pantry(_ name: String, expiresIn days: Int?, now: Date) -> InventoryItem {
        InventoryItem(
            id: UUID(), name: name, quantity: 1, unit: .piece, purchaseDate: nil,
            expirationDate: days.flatMap { calendar.date(byAdding: .day, value: $0, to: now) },
            category: .other, location: .fridge, notes: nil, status: .available, reminderSnoozedUntil: nil
        )
    }

    private func candidate(_ name: String, _ meal: MealType?, protein: Double = 30, items: [String] = [], diets: Set<Recipe.Diet>? = [.pescatarian], allergens: Set<Allergen> = []) -> MealSuggestions.Candidate {
        MealSuggestions.Candidate(
            name: name, mealType: meal,
            nutrition: NutritionFacts(calories: 600, proteinGrams: protein, carbohydrateGrams: 60, fatGrams: 20),
            items: items.map { PlannedMeal.Item(name: $0) }, source: .foods, diets: diets, allergens: allergens
        )
    }

    private func profile(diet: DietaryPreference = .custom, description: String? = "Pescatarian", allergies: Set<Allergen> = [.nuts]) -> UserProfile {
        var profile = MockData(now: .now, calendar: calendar).profile
        profile.dietaryPreference = diet
        profile.customDietDescription = description
        profile.allergies = allergies
        return profile
    }

    @Test("A week has 21 main-meal slots: eaten, planned or open; open counts from today")
    func weekSlots() throws {
        let monday = try TestClock.date(2026, 10, 5, 0)
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let entries = [
            entry("Oats", .breakfast, at: try TestClock.date(2026, 10, 5, 8)),
            entry("Yogurt", .breakfast, at: try TestClock.date(2026, 10, 6, 7, 45)),
            entry("Skyr", .snack, at: try TestClock.date(2026, 10, 6, 16)),
        ]
        let dinner = PlannedMeal(candidate: candidate("Miso cod", .dinner), day: now, meal: .dinner, now: now, calendar: calendar)
        let plan = WeekPlan(weekStart: monday, entries: entries, planned: [dinner], now: now, calendar: calendar)

        #expect(plan.days.count == 7)
        #expect(plan.slotCount == 21)
        #expect(plan.filledCount == 3, "Two breakfasts eaten, tonight's dinner planned; snacks aren't slots")
        #expect(plan.days[0].isPast && plan.days[1].isToday)
        // Today: lunch is open; then 5 future days × 3.
        #expect(plan.openSlots.count == 1 + 15)
        #expect(plan.openSlots.first?.meal == .lunch)
    }

    @Test("A day's dot: all main meals eaten or planned, some, or none; snacks don't count")
    func coverage() throws {
        let monday = try TestClock.date(2026, 10, 5, 0)
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let tuesday = try TestClock.date(2026, 10, 6, 12)
        let entries = [
            entry("Oats", .breakfast, at: try TestClock.date(2026, 10, 5, 8)),
            entry("Poke", .lunch, at: try TestClock.date(2026, 10, 5, 13)),
            entry("Cod", .dinner, at: try TestClock.date(2026, 10, 5, 19)),
            entry("Skyr", .snack, at: try TestClock.date(2026, 10, 7, 16)),
        ]
        let planned = [
            PlannedMeal(candidate: candidate("Miso cod", .dinner), day: tuesday, meal: .dinner, now: now, calendar: calendar),
        ]
        let plan = WeekPlan(weekStart: monday, entries: entries, planned: planned, now: now, calendar: calendar)
        #expect(plan.days[0].coverage == .all && plan.days[0].filledCount == 3)
        #expect(plan.days[1].coverage == .some && plan.days[1].filledCount == 1, "A planned dinner counts")
        #expect(plan.days[2].coverage == .none, "A snack alone isn't a main meal")
    }

    @Test("Ingredients match pantry items by name, longest match first")
    func pantryMatch() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let items = [pantry("Rice", expiresIn: nil, now: now), pantry("Jasmine rice", expiresIn: nil, now: now), pantry("Baby spinach", expiresIn: 1, now: now)]
        #expect(PantryMatch.item(for: "jasmine rice", in: items)?.name == "Jasmine rice")
        #expect(PantryMatch.status(for: "Baby spinach", in: items, now: now, calendar: calendar) == .useSoon(.tomorrow))
        #expect(PantryMatch.status(for: "Rice", in: items, now: now, calendar: calendar) == .inPantry)
        #expect(PantryMatch.status(for: "Salmon fillet", in: items, now: now, calendar: calendar) == .toBuy)
    }

    @Test("Suggestions respect diet and allergies")
    func dietAndAllergies() throws {
        let pescatarian = profile()
        #expect(MealSuggestions.fits(diets: [.pescatarian], profile: pescatarian))
        #expect(MealSuggestions.fits(diets: [.vegetarian], profile: pescatarian))
        #expect(MealSuggestions.fits(diets: nil, profile: pescatarian), "The user's own meals always fit")
        #expect(!MealSuggestions.fits(diets: [], profile: pescatarian), "Meat dishes carry no diet and are left out")
        // Typed in onboarding's "Something else", in any case.
        #expect(!MealSuggestions.fits(diets: [], profile: profile(description: "pescatarian, mostly")))
        let vegetarian = profile(diet: .vegetarian, description: nil)
        #expect(!MealSuggestions.fits(diets: [.pescatarian], profile: vegetarian))

        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let ranked = MealSuggestions.ranked(
            for: .dinner, on: now,
            candidates: [candidate("Satay noodles", .dinner, allergens: [.nuts]), candidate("Miso cod", .dinner)],
            pantry: [], profile: pescatarian, now: now, calendar: calendar
        )
        #expect(ranked.map(\.name) == ["Miso cod"])
    }

    @Test("Meals that use pantry items before they expire come first; then protein fit")
    func ranking() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let items = [pantry("Baby spinach", expiresIn: 2, now: now)]
        let wednesday = try TestClock.date(2026, 10, 7, 0)
        let ranked = MealSuggestions.ranked(
            for: .dinner, on: wednesday,
            candidates: [
                candidate("Salmon & rice", .dinner, protein: 46, items: ["Salmon fillet", "Rice"]),
                candidate("Cod & spinach", .dinner, protein: 20, items: ["Cod", "Baby spinach"]),
                candidate("Tofu bowl", .dinner, protein: 10, items: ["Tofu"]),
            ],
            pantry: items, profile: profile(), now: now, calendar: calendar
        )
        // Spinach expires Thursday, so Wednesday's dinner should use it. Then
        // 46 g is nearest a third of 140 g.
        #expect(ranked.map(\.name) == ["Cod & spinach", "Salmon & rice", "Tofu bowl"])

        // After Thursday the spinach no longer counts.
        let saturday = try TestClock.date(2026, 10, 10, 0)
        let later = MealSuggestions.ranked(for: .dinner, on: saturday, candidates: [
            candidate("Cod & spinach", .dinner, protein: 20, items: ["Cod", "Baby spinach"]),
            candidate("Salmon & rice", .dinner, protein: 46, items: ["Salmon fillet", "Rice"]),
        ], pantry: items, profile: profile(), now: now, calendar: calendar)
        #expect(later.first?.name == "Salmon & rice")
    }

    @Test("Each open slot gets the best fit; nothing repeats in a week; the result is stable")
    func suggest() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let slots: [(day: Date, meal: MealType)] = [
            (try TestClock.date(2026, 10, 7, 0), .dinner),
            (try TestClock.date(2026, 10, 8, 0), .dinner),
            (try TestClock.date(2026, 10, 8, 0), .breakfast),
        ]
        let candidates = [candidate("Miso cod", .dinner), candidate("Fish tacos", .dinner), candidate("Oats", .breakfast)]
        let first = MealSuggestions.suggest(openSlots: slots, candidates: candidates, pantry: [], profile: profile(), excludingNames: ["Fish tacos"], now: now, calendar: calendar)
        #expect(first.map(\.candidate.name) == ["Miso cod", "Oats"], "Fish tacos are already planned; Thursday dinner has nothing left")
        let again = MealSuggestions.suggest(openSlots: slots, candidates: candidates.reversed(), pantry: [], profile: profile(), excludingNames: ["Fish tacos"], now: now, calendar: calendar)
        #expect(again.map(\.candidate.name) == first.map(\.candidate.name))
    }

    @Test("The user's own meals become candidates once per distinct set of foods; quick adds don't")
    func fromLog() throws {
        let day1 = try TestClock.date(2026, 10, 5, 8)
        let day2 = try TestClock.date(2026, 10, 6, 8)
        var quick = entry("Toast", .lunch, at: day2)
        quick.foodID = nil
        let entries = [
            entry("Greek yogurt", .breakfast, at: day1), entry("Oats", .breakfast, at: day1),
            entry("Oats", .breakfast, at: day2), entry("Greek yogurt", .breakfast, at: day2),
            quick,
        ]
        let candidates = MealSuggestions.Candidate.fromLog(entries, allergens: { _ in [] }, calendar: calendar)
        #expect(candidates.count == 1)
        #expect(candidates.first?.mealType == .breakfast)
        #expect(candidates.first?.diets == nil)
    }
}
