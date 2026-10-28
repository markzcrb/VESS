import Foundation
import OSLog

/// Keeps `MirroredProfile` in the user's iCloud key-value storage, so a new
/// install can restore the answers and targets after sign-in. Apple's
/// iCloud, not UMEVA's server. Needs the iCloud capability (a paid team):
/// off unless `VESS_ICLOUD_PROFILE = YES` (Config/Supabase.xcconfig) and the
/// `com.apple.developer.ubiquity-kvstore-identifier` entitlement. Off, it
/// keeps nothing and finds nothing, and the app offers the other ways back.
@Observable
final class ProfileMirror {
    nonisolated protocol Storage: Sendable {
        func data() -> Data?
        func set(_ data: Data?)
        /// Asks iCloud for the latest copy (a new install may not have it yet).
        func refresh() async
    }

    private let storage: (any Storage)?
    private let logger = Logger(subsystem: AppLog.subsystem, category: "ProfileMirror")
    static let key = "profile.v\(MirroredProfile.version)"

    init(storage: (any Storage)?) {
        self.storage = storage
    }

    var isEnabled: Bool { storage != nil }

    /// Written whenever the profile changes.
    func save(_ profile: UserProfile, calendar: Calendar = .current) {
        guard let storage else { return }
        do {
            storage.set(try JSONEncoder().encode(MirroredProfile(profile, calendar: calendar)))
        } catch {
            logger.error("Mirroring the profile failed")
        }
    }

    /// The copy in iCloud, if there is one.
    func load() async -> MirroredProfile? {
        guard let storage else { return nil }
        if storage.data() == nil { await storage.refresh() }
        return storage.data().flatMap { try? JSONDecoder().decode(MirroredProfile.self, from: $0) }
    }

    /// Delete all data: the iCloud copy goes too.
    func clear() {
        storage?.set(nil)
    }

    static func make() -> ProfileMirror {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTesting") {
            let memory = MemoryStorage()
            // `-mirroredProfileDemo`: a copy in "iCloud" to restore (UI tests).
            if arguments.contains("-mirroredProfileDemo") {
                let demo = MockData(now: AppClock.now, calendar: .current).profile
                memory.set(try? JSONEncoder().encode(MirroredProfile(demo, calendar: .current)))
            }
            return ProfileMirror(storage: memory)
        }
        #endif
        let enabled = (Bundle.main.object(forInfoDictionaryKey: "VESSICloudProfile") as? String)?.uppercased() == "YES"
        return ProfileMirror(storage: enabled ? CloudStorage() : nil)
    }

    /// NSUbiquitousKeyValueStore.
    nonisolated struct CloudStorage: Storage {
        func data() -> Data? { NSUbiquitousKeyValueStore.default.data(forKey: ProfileMirror.key) }

        func set(_ data: Data?) {
            let store = NSUbiquitousKeyValueStore.default
            if let data { store.set(data, forKey: ProfileMirror.key) } else { store.removeObject(forKey: ProfileMirror.key) }
            store.synchronize()
        }

        /// Up to 3 s for iCloud's first delivery after an install.
        func refresh() async {
            NSUbiquitousKeyValueStore.default.synchronize()
            for _ in 0..<15 where data() == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// Tests and DEBUG launch flags.
    nonisolated final class MemoryStorage: Storage, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Data?
        func data() -> Data? { lock.withLock { stored } }
        func set(_ data: Data?) { lock.withLock { stored = data } }
        func refresh() async {}
    }
}
