import Foundation
import Testing
@testable import VESS

@Suite("Today rings: choice, order, limits")
struct TodayRingTests {
    @Test("Profiles from before (nil) get the default: Fuel, Energy, Protein, Water, Steps")
    func defaultForExistingUsers() throws {
        let profile = MockData(now: .now, calendar: TestClock.utc).profile
        #expect(profile.todayRings == nil)
        #expect(profile.todayRingList == [.fuel, .energy, .protein, .water, .steps])
        // A stored profile without the key decodes and still gets the default.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any] ?? [:]
        json.removeValue(forKey: "todayRings")
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.todayRingList == TodayRingRules.defaultRings)
    }

    @Test("The stored order is kept; unknown and repeated rings are dropped; at most 12; empty is the default")
    func sanitized() {
        #expect(TodayRingRules.rings(stored: ["sleep", "fuel", "sleep", "somethingNew", "caffeine"], cycleTrackingOn: false) == [.sleep, .fuel, .caffeine])
        let all = TodayRing.allCases.map(\.rawValue)
        #expect(TodayRingRules.rings(stored: all, cycleTrackingOn: true).count == 12)
        #expect(TodayRingRules.rings(stored: [], cycleTrackingOn: false) == TodayRingRules.defaultRings)
    }

    @Test("Cycle day only while cycle tracking is on")
    func cycleGate() {
        #expect(!TodayRingRules.available(cycleTrackingOn: false).contains(.cycleDay))
        #expect(TodayRingRules.available(cycleTrackingOn: true).contains(.cycleDay))
        #expect(TodayRingRules.rings(stored: ["cycleDay", "water"], cycleTrackingOn: false) == [.water])
    }

    @Test("At least 1 ring and at most 12")
    func limits() {
        #expect(TodayRingRules.removing(.fuel, from: [.fuel]) == [.fuel], "The last ring can't be removed")
        let twelve = Array(TodayRing.allCases.prefix(12))
        #expect(TodayRingRules.adding(.habits, to: twelve) == twelve, "No 13th ring")
        #expect(TodayRingRules.adding(.sleep, to: [.fuel]) == [.fuel, .sleep])
        #expect(TodayRingRules.adding(.fuel, to: [.fuel]) == [.fuel], "No duplicates")
    }

    @Test("Health rings show — until Health has data; nutrition rings are percent of target")
    func readings() throws {
        let now = try TestClock.date(2026, 10, 6, 18, 40)
        let data = MockData(now: now, calendar: TestClock.utc)
        let summary = DaySummary(entries: data.foodLog, hydrationLogs: data.hydrationLog, targets: data.profile.nutritionTargets,
                                 waterTargetMilliliters: data.profile.waterTargetMilliliters, day: now, now: now, calendar: TestClock.utc)
        func readings(_ snapshot: HealthSnapshot?) -> [TodayRingReading] {
            TodayRingReading.readings([.energy, .sleep, .restingHeartRate, .stress, .steps], input: .init(
                profile: data.profile, summary: summary, fuel: nil, snapshot: snapshot, caffeineMilligrams: 0,
                habitsDone: 0, habitsListed: 0, cycleDay: nil, cycleLength: nil, now: now, calendar: TestClock.utc
            ))
        }
        let none = readings(nil)
        #expect(none.dropFirst().allSatisfy { $0.value == TodayRingReading.empty && $0.progress == 0 })
        #expect(Int(none[0].value) != nil, "Energy is a percent")
        let demo = readings(data.health)
        #expect(demo[1].value == "7:12" && demo[2].value == "58" && demo[3].value == "Calm")
    }
}
