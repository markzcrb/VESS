import Foundation
import OSLog

/// DEBUG: how long a cold launch takes, and any main-thread stall in the
/// first 15 s. Console: subsystem "VESS", category "Launch".
///
/// - `process → init`: dyld and the runtime, before any VESS code.
/// - `init → store`: opening (and, with DEBUG flags, seeding) the store.
/// - `→ first frame`: until the first screen is on screen.
/// - `stall N ms`: the main thread didn't answer a ping for N ms.
enum LaunchTiming {
    #if DEBUG
    private static let logger = Logger(subsystem: "VESS", category: "Launch")
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
    #endif

    static func appInit() {
        #if DEBUG
        initDate = .now
        logger.notice("process → init \(ms(processStart), privacy: .public) ms")
        startWatchdog()
        #endif
    }

    static func mark(_ step: StaticString) {
        #if DEBUG
        logger.notice("init → \(step, privacy: .public) \(ms(initDate), privacy: .public) ms")
        #endif
    }

    static func firstFrame() {
        #if DEBUG
        guard !reportedFirstFrame else { return }
        reportedFirstFrame = true
        logger.notice("process → first frame \(ms(processStart), privacy: .public) ms (init → first frame \(ms(initDate), privacy: .public) ms)")
        #endif
    }

    #if DEBUG
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
    #endif
}
