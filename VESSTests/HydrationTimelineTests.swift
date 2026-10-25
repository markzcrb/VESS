import Foundation
import Testing
@testable import VESS

@Suite("Drinks timeline")
struct HydrationTimelineTests {
    private let calendar = TestClock.utc

    private func drink(_ hour: Int, _ minute: Int) throws -> HydrationLog {
        DrinkPreset.espresso.drink(name: "Espresso")
            .log(userID: UUID(), volumeMilliliters: 60, at: try TestClock.date(2026, 10, 6, hour, minute))
    }

    @Test("From 06 normally; from 00 when a drink or now is before 06, so nothing sits away from its time")
    func startHour() throws {
        let day = [try drink(9, 10), try drink(13, 0)]
        #expect(HydrationTimeline.startHour(logs: day, now: try TestClock.date(2026, 10, 6, 18, 40), calendar: calendar) == 6)
        #expect(HydrationTimeline.startHour(logs: day + [try drink(0, 33)], now: nil, calendar: calendar) == 0, "A 00:33 drink")
        #expect(HydrationTimeline.startHour(logs: [], now: try TestClock.date(2026, 10, 6, 1, 15), calendar: calendar) == 0, "Now is 01:15")
        #expect(HydrationTimeline.startHour(logs: [try drink(6, 0)], now: nil, calendar: calendar) == 6, "06:00 is on the 06 axis")
    }
}
