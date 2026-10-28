import Foundation
import OSLog
import Synchronization

/// Runs each Apple Health read on its own: a read that fails gives its
/// empty value and is recorded, so one failing type (sleep, say) never
/// takes the others (steps) down with it.
nonisolated final class HealthReadLog: Sendable {
    private let failures = Mutex<[HealthDataKind: String]>([:])
    private let logger = Logger(subsystem: AppLog.subsystem, category: "Health")

    /// The kinds that failed, with a description of the error.
    var issues: [HealthDataKind: String] { failures.withLock { $0 } }

    func read<Value: Sendable>(_ kind: HealthDataKind, empty: Value, _ operation: @Sendable () async throws -> Value) async -> Value {
        do {
            return try await operation()
        } catch {
            let description = Self.describe(error)
            logger.error("Health read \(kind.rawValue, privacy: .public) failed: \(description, privacy: .public)")
            failures.withLock { $0[kind] = description }
            return empty
        }
    }

    /// "HKErrorDomain 5: Authorization not determined", so the real cause
    /// shows in the log and on the Debug Apple Health screen.
    static func describe(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
