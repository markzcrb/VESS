import Foundation
import Testing
@testable import MyApp

@MainActor
@Suite("Local store")
struct LocalStoreTests {
    @Test("A profile saved to the store can be read back")
    func profileRoundTrip() throws {
        let store = try LocalStore.inMemory()
        #expect(store.profile == nil)

        var profile = MockData(now: .now, calendar: TestClock.utc).profile
        profile.hydrationContributionOverrides = [.flatWhite: 85]
        try store.saveProfile(profile)

        #expect(store.profile?.id == profile.id)
        #expect(store.profile?.hydrationContributionOverrides?[.flatWhite] == 85)
    }

    @Test("Food entries are returned for their day only, oldest first")
    func foodEntriesByDay() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 3, 10, 18)
        let data = MockData(now: now, calendar: TestClock.utc)
        for entry in data.foodLog.reversed() { try store.add(entry) }

        let today = store.foodEntries(on: now, calendar: TestClock.utc)
        #expect(today.count == data.foodLog.count)
        #expect(today.map(\.loggedAt) == today.map(\.loggedAt).sorted())

        let yesterday = try TestClock.date(2026, 3, 9, 12)
        #expect(store.foodEntries(on: yesterday, calendar: TestClock.utc).isEmpty)
    }

    @Test("Deleting a hydration log removes it, which is how Undo works")
    func deleteHydration() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 3, 10, 18)
        let log = DrinkPreset.water.drink(name: "Water").log(userID: UUID(), volumeMilliliters: 250, at: now)

        try store.add(log)
        #expect(store.hydrationLogs(on: now, calendar: TestClock.utc).map(\.id) == [log.id])

        try store.deleteHydrationLog(id: log.id)
        #expect(store.hydrationLogs(on: now, calendar: TestClock.utc).isEmpty)
    }

    @Test("Deleting all data clears every record and the profile")
    func deleteAll() throws {
        let store = try LocalStore.inMemory()
        let now = try TestClock.date(2026, 3, 10, 18)
        try store.seed(MockData(now: now, calendar: TestClock.utc))
        #expect(store.profile != nil)

        try store.deleteAllData()

        #expect(store.profile == nil)
        #expect(store.foodEntries(on: now, calendar: TestClock.utc).isEmpty)
        #expect(store.hydrationLogs(on: now, calendar: TestClock.utc).isEmpty)
        #expect(store.inventory.isEmpty)
    }
}

@MainActor
@Suite("Onboarding")
struct OnboardingDraftTests {
    private func completeDraft() -> OnboardingDraft {
        let draft = OnboardingDraft()
        draft.name = " Mark "
        draft.goal = .buildMuscle
        draft.ageText = "29"
        draft.sex = .male
        draft.heightText = "178"
        draft.weightText = "68,5"
        draft.activityLevel = .moderate
        draft.dietaryPreference = .highProtein
        return draft
    }

    @Test("Basics require plausible values")
    func basicsValidation() {
        let draft = completeDraft()
        #expect(draft.isComplete(.basics))

        draft.ageText = "8"
        #expect(!draft.isComplete(.basics))
        draft.ageText = "29"

        draft.heightText = "17.8"
        #expect(!draft.isComplete(.basics))
    }

    @Test("A custom diet needs a description")
    func customDiet() {
        let draft = completeDraft()
        draft.dietaryPreference = .custom
        #expect(!draft.isComplete(.diet))
        draft.customDiet = "Pescatarian"
        #expect(draft.isComplete(.diet))
    }

    @Test("The finished profile has calculated targets and trimmed answers")
    func makeProfile() throws {
        let now = try TestClock.date(2026, 3, 10)
        let profile = try #require(completeDraft().makeProfile(prefersAppleHealth: false, now: now, calendar: TestClock.utc))

        #expect(profile.name == "Mark")
        #expect(profile.weightKilograms == 68.5)
        #expect(profile.age(on: now, calendar: TestClock.utc) == 29)
        #expect(profile.prefersAppleHealth == false)
        #expect(profile.nutritionTargets.calories > 0)
        #expect(profile.waterTargetMilliliters == NutritionTargetCalculator.waterTargetMilliliters(weightKilograms: 68.5))
    }

    @Test("An incomplete draft makes no profile")
    func incomplete() {
        let draft = completeDraft()
        draft.goal = nil
        #expect(draft.makeProfile(prefersAppleHealth: true, now: .now, calendar: TestClock.utc) == nil)
    }
}
