import Foundation

/// Remembers, per feature, which consent version the user allowed.
@Observable
final class AIConsentStore {
    private let defaults: UserDefaults
    /// Mirrors the defaults so views update when consent changes.
    private var versions: [AIFeature: Int]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        versions = Dictionary(uniqueKeysWithValues: AIFeature.allCases.map { ($0, defaults.integer(forKey: AIConsentRules.key($0))) })
    }

    func isGranted(_ feature: AIFeature) -> Bool {
        AIConsentRules.isGranted(storedVersion: versions[feature] ?? 0, current: AIProcessor.consentVersion(for: feature))
    }

    func grant(_ feature: AIFeature) {
        set(AIProcessor.consentVersion(for: feature), for: feature)
    }

    func revoke(_ feature: AIFeature) {
        set(0, for: feature)
    }

    func revokeAll() {
        AIFeature.allCases.forEach(revoke)
    }

    private func set(_ version: Int, for feature: AIFeature) {
        versions[feature] = version
        defaults.set(version, forKey: AIConsentRules.key(feature))
    }

    /// The device's settings, or with DEBUG launch flags a throwaway suite
    /// (`-aiConsentGranted` starts with both allowed, for captures).
    static func make() -> AIConsentStore {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-aiMock") || arguments.contains("-uiTesting") {
            let suite = "VESS.debugConsent"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            let store = AIConsentStore(defaults: defaults)
            if arguments.contains("-aiConsentGranted") { AIFeature.allCases.forEach(store.grant) }
            return store
        }
        #endif
        return AIConsentStore(defaults: .standard)
    }
}
