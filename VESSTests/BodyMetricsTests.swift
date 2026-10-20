import Foundation
import Testing
@testable import VESS

@Suite("Body metrics")
struct BodyMetricsTests {
    @Test("BMI is weight divided by height in meters squared")
    func bmiValue() throws {
        let bmi = try #require(BodyMassIndex(weightKilograms: 68, heightCentimeters: 178))

        // 68 / 1.78²
        #expect(bmi.value.isApproximately(21.4619, tolerance: 0.0001))
    }

    @Test("BMI is unavailable for non-positive inputs", arguments: [(0.0, 178.0), (68.0, 0.0), (-1.0, 178.0)])
    func bmiInvalid(weight: Double, height: Double) {
        #expect(BodyMassIndex(weightKilograms: weight, heightCentimeters: height) == nil)
    }

    @Test("Age comes from date of birth, so it never goes stale")
    func ageFromDateOfBirth() throws {
        let now = try TestClock.date(2026, 3, 10)
        var profile = MockData(now: now, calendar: TestClock.utc).profile

        #expect(profile.age(on: now, calendar: TestClock.utc) == 29)

        // The day before the 30th birthday is still 29.
        profile.dateOfBirth = try TestClock.date(1996, 3, 11)
        #expect(profile.age(on: now, calendar: TestClock.utc) == 29)

        profile.dateOfBirth = nil
        #expect(profile.age(on: now, calendar: TestClock.utc) == nil)
    }
}
