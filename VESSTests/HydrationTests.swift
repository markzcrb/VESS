import Foundation
import Testing
@testable import VESS

@Suite("Hydration")
struct HydrationTests {
    @Test("Today's progress sums hydration contributions, not raw volume")
    func mockProgress() throws {
        let now = try TestClock.date(2026, 3, 10, 18)
        let data = MockData(now: now, calendar: TestClock.utc)

        let progress = HydrationProgress(
            logs: data.hydrationLog,
            targetMilliliters: data.profile.waterTargetMilliliters,
            day: now,
            calendar: TestClock.utc
        )

        // Water 500 + sparkling 330 + green tea 300 × 90% + water 500 (DATA.md).
        // The prior days' drinks are excluded.
        #expect(progress.consumedMilliliters.isApproximately(500 + 330 + 270 + 500))
        #expect(progress.volumeMilliliters == 1630)
        #expect(progress.targetMilliliters == 2200)
        #expect(!progress.isTargetReached)
    }

    @Test("A 240 ml flat white contributes about 190 ml and keeps its full volume")
    func partialContribution() throws {
        let flatWhite = DrinkPreset.flatWhite.drink(name: "Flat white")
        let log = flatWhite.log(userID: UUID(), volumeMilliliters: 240, at: .now)

        #expect(log.volumeMilliliters == 240)
        #expect(log.hydrationMilliliters.isApproximately(189.6))
        // Nutrition scales with the full volume, independent of hydration.
        #expect(log.calories.isApproximately(46 * 2.4))
        #expect(log.caffeineMilligrams.isApproximately(54 * 2.4))
    }

    @Test("A per-log percentage overrides the drink default")
    func perLogOverride() {
        let coffee = DrinkPreset.blackCoffee.drink(name: "Coffee")
        let log = coffee.log(userID: UUID(), volumeMilliliters: 200, hydrationContributionPercent: 50, at: .now)

        #expect(log.hydrationContributionPercent == 50)
        #expect(log.hydrationMilliliters == 100)
    }

    @Test("The user's saved default wins over the preset default")
    func profileOverride() throws {
        var profile = MockData(now: .now, calendar: TestClock.utc).profile
        #expect(profile.hydrationContributionPercent(for: .flatWhite) == 79)

        profile.hydrationContributionOverrides = [.flatWhite: 90]
        #expect(profile.hydrationContributionPercent(for: .flatWhite) == 90)
        #expect(profile.hydrationContributionPercent(for: .water) == 100)
    }

    @Test("Percentages outside 0–100 are clamped")
    func contributionClamped() {
        let water = DrinkPreset.water.drink(name: "Water")
        let over = water.log(userID: UUID(), volumeMilliliters: 100, hydrationContributionPercent: 150, at: .now)
        let under = water.log(userID: UUID(), volumeMilliliters: 100, hydrationContributionPercent: -20, at: .now)

        #expect(over.hydrationMilliliters == 100)
        #expect(under.hydrationMilliliters == 0)
    }

    @Test("Progress is clamped at 100% and safe with no target")
    func clamping() throws {
        let now = try TestClock.date(2026, 3, 10, 18)
        let water = DrinkPreset.water.drink(name: "Water")
        let logs = [water.log(userID: UUID(), volumeMilliliters: 3000, at: now)]

        let over = HydrationProgress(logs: logs, targetMilliliters: 2000, day: now, calendar: TestClock.utc)
        #expect(over.fractionComplete == 1)
        #expect(over.remainingMilliliters == 0)
        #expect(over.isTargetReached)

        let noTarget = HydrationProgress(logs: logs, targetMilliliters: 0, day: now, calendar: TestClock.utc)
        #expect(noTarget.fractionComplete == 0)
        #expect(!noTarget.isTargetReached)
    }
}
