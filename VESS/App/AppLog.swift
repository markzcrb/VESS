import Foundation

/// The one subsystem for every `Logger` in the app: the bundle ID, so logs
/// follow the app's identity without a hard-coded name.
nonisolated enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "UMEVA"
}
