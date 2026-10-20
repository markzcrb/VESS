import Foundation
import Testing
@testable import VESS

@Suite("Expiration")
struct ExpirationTests {
    @Test(
        "Status is based on calendar days from today",
        arguments: zip(
            [-2, 0, 1, 2, 3, 4],
            [
                ExpirationStatus.expired(daysAgo: 2),
                .today,
                .tomorrow,
                .soon(days: 2),
                .soon(days: 3),
                .later(days: 4),
            ]
        )
    )
    func statusByDayOffset(offset: Int, expected: ExpirationStatus) throws {
        let now = try TestClock.date(2026, 3, 10, 15)
        let expiration = try #require(TestClock.utc.date(byAdding: .day, value: offset, to: now))

        #expect(ExpirationStatus(expirationDate: expiration, now: now, calendar: TestClock.utc) == expected)
    }

    @Test("Time of day doesn't matter, only the calendar day")
    func ignoresTimeOfDay() throws {
        let lateTonight = try TestClock.date(2026, 3, 10, 23, 30)
        let justAfterMidnight = try TestClock.date(2026, 3, 11, 0, 15)

        #expect(ExpirationStatus(expirationDate: justAfterMidnight, now: lateTonight, calendar: TestClock.utc) == .tomorrow)
    }

    @Test("A daylight saving change doesn't shift the day count")
    func daylightSavingBoundary() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        // Clocks move forward on 29 March 2026, so that day has 23 hours.
        let now = try TestClock.date(2026, 3, 28, 22, calendar: berlin)
        let expiration = try TestClock.date(2026, 3, 30, 8, calendar: berlin)

        #expect(ExpirationStatus(expirationDate: expiration, now: now, calendar: berlin) == .soon(days: 2))
    }

    @Test("Items without a date never need attention")
    func noDate() {
        let status = ExpirationStatus(expirationDate: nil, now: .now, calendar: TestClock.utc)

        #expect(status == .noDate)
        #expect(!status.needsAttention)
    }

    @Test("Mock inventory surfaces strawberries, chicken and avocado as expiring")
    func mockInventory() throws {
        let now = try TestClock.date(2026, 3, 10, 18)
        let data = MockData(now: now, calendar: TestClock.utc)

        let statuses = Dictionary(uniqueKeysWithValues: data.inventory.map {
            ($0.name, $0.expirationStatus(now: now, calendar: TestClock.utc))
        })
        #expect(statuses["Strawberries"] == .tomorrow)
        #expect(statuses["Chicken breast"] == .soon(days: 2))

        let needsAttention = data.inventory
            .filter { $0.expirationStatus(now: now, calendar: TestClock.utc).needsAttention }
            .map(\.name)
        #expect(Set(needsAttention) == ["Strawberries", "Chicken breast", "Avocado"])
    }
}
