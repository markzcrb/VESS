import Foundation

/// The app's "now". Views read the time from here instead of `Date.now`.
///
/// DEBUG builds pin it to the demo moment from `Redesign/docs/DATA.md`,
/// Tuesday 6 October 2026 at 18:40 local time, in Xcode previews and when
/// launched with `-demoClock`, so previews and captures never depend on the
/// real time. Release builds always use the real clock.
nonisolated enum AppClock {
    static var now: Date {
        #if DEBUG
        if let demo { return demo }
        #endif
        return .now
    }

    #if DEBUG
    /// Tuesday 6 October 2026, 18:40.
    static let demoMoment: Date = {
        let components = DateComponents(year: 2026, month: 10, day: 6, hour: 18, minute: 40)
        return Calendar.current.date(from: components) ?? .now
    }()

    private static let demo: Date? = {
        let process = ProcessInfo.processInfo
        let isPreview = process.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        return isPreview || process.arguments.contains("-demoClock") ? demoMoment : nil
    }()
    #endif
}
