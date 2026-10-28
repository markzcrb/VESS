import Foundation
import OSLog

/// How long a cold launch takes, and any main-thread stall in the first
/// 15 s. On in DEBUG, or in any build with `-launchTiming` (to measure
/// Release). Console: subsystem "VESS", category "Launch".
///
/// - `process → init`: dyld and the runtime, before any VESS code.
/// - `init → store`: opening (and, with DEBUG flags, seeding) the store.
/// - `→ first frame`: until the first screen is on screen.
/// - `stall N ms`: the main thread didn't answer a ping for N ms.
enum LaunchTiming {
    private static let isOn: Bool = {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.arguments.contains("-launchTiming")
        #endif
    }()
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "Launch")
    nonisolated(unsafe) private static var initDate: Date?
    nonisolated(unsafe) private static var reportedFirstFrame = false

    /// When the process started (kernel's record), so pre-main time counts.
    private static var processStart: Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    private static func ms(_ from: Date?, _ to: Date = .now) -> Int {
        from.map { Int(to.timeIntervalSince($0) * 1000) } ?? -1
    }

    static func appInit() {
        guard isOn else { return }
        initDate = .now
        logger.notice("process → init \(ms(processStart), privacy: .public) ms")
        startWatchdog()
    }

    static func mark(_ step: StaticString) {
        guard isOn else { return }
        logger.notice("init → \(step, privacy: .public) \(ms(initDate), privacy: .public) ms")
        print("LaunchTiming \(step) \(ms(initDate)) ms after init")
    }

    static func firstFrame() {
        guard isOn, !reportedFirstFrame else { return }
        reportedFirstFrame = true
        let total = ms(processStart), sinceInit = ms(initDate)
        logger.notice("process → first frame \(total, privacy: .public) ms (init → first frame \(sinceInit, privacy: .public) ms)")
        // Also on stdout, so `devicectl … --console` can read it from a device.
        print("LaunchTiming first frame \(total) ms (init \(sinceInit) ms)")
    }

    /// Runs `work` and logs it when it takes over 50 ms (during the first
    /// 15 s), to name main-thread stalls.
    static func timed<T>(_ label: StaticString, _ work: () -> T) -> T {
        guard isOn, let initDate, Date().timeIntervalSince(initDate) < 15 else { return work() }
        let start = Date()
        let result = work()
        let took = ms(start)
        if took > 50 { logger.notice("\(label, privacy: .public) \(took, privacy: .public) ms at +\(ms(initDate, start), privacy: .public) ms") }
        return result
    }

    /// Pings the main thread every 100 ms for 15 s; logs answers later than 250 ms.
    private static func startWatchdog() {
        Thread.detachNewThread {
            let end = Date().addingTimeInterval(15)
            while Date() < end {
                let sent = Date()
                let answered = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { answered.signal() }
                answered.wait()
                let waited = Int(Date().timeIntervalSince(sent) * 1000)
                if waited > 250 {
                    logger.notice("stall \(waited, privacy: .public) ms at +\(ms(initDate, sent), privacy: .public) ms")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            logger.notice("watchdog done")
        }
    }
}
