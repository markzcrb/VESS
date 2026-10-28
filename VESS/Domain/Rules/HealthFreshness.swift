import Foundation

/// Whether Apple Health's values on screen are out of date: the last read
/// failed (the last known values stay), or the last successful read was
/// more than an hour ago. Today then dims its Health rings and says when
/// Health was last updated, with Retry. Pure.
nonisolated enum HealthFreshness {
    static let staleAfter: TimeInterval = 3600

    static func isStale(_ state: HealthSyncState, lastSuccess: Date?, now: Date) -> Bool {
        switch state {
        case .failed(let lastKnown):
            return lastKnown != nil
        case .available:
            guard let lastSuccess else { return false }
            return now.timeIntervalSince(lastSuccess) > staleAfter
        case .notConnected, .nothingShared, .syncing:
            return false
        }
    }

    /// How long ago, for "updated 3 h ago".
    nonisolated enum Age: Equatable, Sendable {
        case minutes(Int)
        case hours(Int)
        case days(Int)
    }

    static func age(since date: Date, now: Date) -> Age {
        let minutes = max(Int(now.timeIntervalSince(date) / 60), 0)
        if minutes < 60 { return .minutes(max(minutes, 1)) }
        if minutes < 24 * 60 { return .hours(minutes / 60) }
        return .days(minutes / (24 * 60))
    }
}
