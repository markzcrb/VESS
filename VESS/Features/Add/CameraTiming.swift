import Foundation
import OSLog

/// How long Photo's camera takes to open: from the tap (or Add opening on
/// Photo) to the sheet being visible, `startRunning` returning, and the
/// first preview frame. Signpost intervals in Instruments (subsystem's
/// "CameraTiming"); with `-cameraTiming` also printed for the console.
/// Timings only, never user data.
nonisolated enum CameraTiming {
    private static let signposter = OSSignposter(subsystem: AppLog.subsystem, category: "CameraTiming")
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "CameraTiming")
    static let isPrinting = ProcessInfo.processInfo.arguments.contains("-cameraTiming")

    private struct Run {
        var start: Date
        var state: OSSignpostIntervalState
        var marked: Set<String> = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var run: Run?

    /// The tap on Photo, or Add opening on Photo.
    static func tapped() {
        lock.withLock {
            run = Run(start: .now, state: signposter.beginInterval("Open camera"))
        }
    }

    /// "sheet", "start" (startRunning returned) and "frame" (first preview
    /// frame), each once per open; the last of "start" and "frame" ends it.
    static func mark(_ step: String) {
        let elapsed: Int? = lock.withLock {
            guard var current = run, !current.marked.contains(step) else { return nil }
            current.marked.insert(step)
            run = current
            let ms = Int(Date.now.timeIntervalSince(current.start) * 1000)
            signposter.emitEvent("Camera step", "\(step, privacy: .public) \(ms, privacy: .public) ms")
            // Done once the first frame is in and startRunning has returned.
            if current.marked.isSuperset(of: ["frame", "start"]) {
                signposter.endInterval("Open camera", current.state)
                run = nil
            }
            return ms
        }
        guard let elapsed else { return }
        logger.notice("camera \(step, privacy: .public) \(elapsed, privacy: .public) ms after tap")
        if isPrinting { print("CameraTiming \(step) \(elapsed) ms") }
    }
}
