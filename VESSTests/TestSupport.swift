import Foundation
import Testing

/// Fixed calendar and dates so tests don't depend on the device's clock or time zone.
enum TestClock {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 12, _ minute: Int = 0,
        calendar: Calendar = utc
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }
}

extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 0.001) -> Bool {
        abs(self - other) <= tolerance
    }
}
