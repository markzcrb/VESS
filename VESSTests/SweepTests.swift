import Foundation
import Testing
@testable import VESS

@Suite("Sweep: onboarding diet, stale Health, one energy number, diary headers, quiet hours")
@MainActor
struct SweepTests {
    private let calendar = TestClock.utc

    @Test("Onboarding writes P01's diet and preferences; the calculator gets the matching diet")
    func onboardingDiet() throws {
        let draft = OnboardingDraft()
        draft.goal = .maintainWeight
        draft.ageText = "34"
        draft.sex = .male
        draft.heightText = "180"
        draft.weightText = "78"
        draft.activityLevel = .moderate
        #expect(!draft.isComplete(.diet))
        draft.diet = .pescatarian
        draft.alsoPrefer = [.highProtein, .glutenFree]
        draft.otherRestriction = "Coriander"
        #expect(draft.isComplete(.diet))
        let profile = try #require(draft.makeProfile(prefersAppleHealth: false, now: .now, calendar: calendar))
        #expect(profile.nutritionPreferences?.diet == .pescatarian)
        #expect(profile.nutritionPreferences?.alsoPrefer == [.highProtein, .glutenFree])
        #expect(profile.nutritionPreferences?.avoidIngredients == ["Coriander"])
        #expect(profile.dietaryPreference == .highProtein)
    }

    @Test("Health is stale after a failed read or an hour without a successful one")
    func staleHealth() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let snapshot = MockData(now: now, calendar: calendar).health
        #expect(!HealthFreshness.isStale(.available(snapshot), lastSuccess: now.addingTimeInterval(-59 * 60), now: now))
        #expect(HealthFreshness.isStale(.available(snapshot), lastSuccess: now.addingTimeInterval(-61 * 60), now: now))
        #expect(!HealthFreshness.isStale(.available(snapshot), lastSuccess: nil, now: now), "A demo store that never read isn't stale")
        #expect(HealthFreshness.isStale(.failed(lastKnown: snapshot), lastSuccess: now, now: now))
        #expect(!HealthFreshness.isStale(.failed(lastKnown: nil), lastSuccess: nil, now: now), "Nothing shown, nothing to dim")
        #expect(!HealthFreshness.isStale(.notConnected, lastSuccess: nil, now: now))
        #expect(HealthFreshness.age(since: now.addingTimeInterval(-3 * 3600), now: now) == .hours(3))
        #expect(HealthFreshness.age(since: now.addingTimeInterval(-90), now: now) == .minutes(1))
    }

    @Test("Today, Macros and Energy show the same kcal: drinks included, rounded once")
    func oneEnergyNumber() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let data = MockData(now: now, calendar: calendar)
        let entries = (data.foodLog + data.foodHistory).filter { $0.loggedAt <= now }
        let summary = DaySummary(entries: entries, hydrationLogs: data.hydrationLog, targets: data.profile.nutritionTargets,
                                 waterTargetMilliliters: data.profile.waterTargetMilliliters, day: now, now: now, calendar: calendar)
        let macros = MacrosDetailView.dailyTotals(entries, drinks: data.hydrationLog, endingOn: now, days: 1, calendar: calendar)
        let today = VESSFormat.calories(summary.consumed.calories)
        #expect(VESSFormat.calories(macros.last?.nutrition.calories ?? 0) == today)
        #expect(data.hydrationLog.contains { calendar.isDate($0.loggedAt, inSameDayAs: now) && $0.energyCalories > 0 },
                "The demo day has a drink with kcal, so the old gap would show")
    }

    @Test("Diary headers show their detail whenever the section has items; \"—\" only when empty")
    func diaryHeaders() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let data = MockData(now: now, calendar: calendar)
        let lunch = data.foodLog.filter { $0.mealType == .lunch }
        #expect(!lunch.isEmpty && DiaryHeaderDetail.meal(lunch) != nil)
        #expect(DiaryHeaderDetail.meal([]) == nil)
        let drinks = data.hydrationLog.filter { calendar.isDate($0.loggedAt, inSameDayAs: now) }
        let detail = try #require(DiaryHeaderDetail.drinks(drinks))
        #expect(detail.contains("\u{00A0}L · "))
        #expect(DiaryHeaderDetail.drinks([]) == nil)
    }

    @Test("Quiet hours: across midnight, within a day, none; every reminder kind keeps them")
    func quietHours() throws {
        let standard = QuietHours.standard
        #expect(standard.contains(try TestClock.date(2026, 10, 6, 23), calendar: calendar))
        #expect(standard.contains(try TestClock.date(2026, 10, 6, 6, 59), calendar: calendar))
        #expect(!standard.contains(try TestClock.date(2026, 10, 6, 7), calendar: calendar))
        let afternoon = QuietHours(start: 13 * 60, end: 15 * 60)
        #expect(afternoon.contains(try TestClock.date(2026, 10, 6, 14), calendar: calendar))
        #expect(!afternoon.contains(try TestClock.date(2026, 10, 6, 15), calendar: calendar))
        #expect(!QuietHours(start: 600, end: 600).contains(try TestClock.date(2026, 10, 6, 10), calendar: calendar))
        #expect(standard.firstAllowed(atOrAfter: try TestClock.date(2026, 10, 6, 23), calendar: calendar) == (try TestClock.date(2026, 10, 7, 7)))
        #expect(standard.firstAllowed(atOrAfter: try TestClock.date(2026, 10, 6, 5), calendar: calendar) == (try TestClock.date(2026, 10, 6, 7)))

        // A habit at 12:30 is dropped when quiet hours cover lunchtime.
        let now = try TestClock.date(2026, 10, 6, 8)
        let habit = Habit(id: UUID(), name: "Walk", schedule: .daily, category: .movement,
                          reminder: DateComponents(hour: 12, minute: 30), auto: nil, createdAt: now)
        let log = HabitRules.Log(checks: [], calendar: calendar)
        #expect(!HabitRules.reminders([habit], log: log, now: now, calendar: calendar, days: 1).isEmpty)
        #expect(HabitRules.reminders([habit], log: log, now: now, calendar: calendar, days: 1,
                                     quiet: QuietHours(start: 12 * 60, end: 13 * 60)).isEmpty)
    }
}
