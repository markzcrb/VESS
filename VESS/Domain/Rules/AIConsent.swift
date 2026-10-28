import Foundation

/// Who processes Coach questions, photos and AI Chef, behind UMEVA's
/// server. The server picks the provider (`AI_PROVIDER`); the app only
/// names it, from here. Switching provider: change `active` and bump
/// `processorVersion`, so everyone is asked again before anything goes to
/// the new one. Ship that app update before the server switches.
nonisolated enum AIProcessor: Sendable {
    case gemini
    case anthropic

    /// The provider the consent text names: Anthropic (Claude Haiku 5.5 on
    /// the server). No fallback to another provider.
    static let active: AIProcessor = .anthropic
    /// Bump with `active`. 2: Anthropic, so every feature asks again.
    static let processorVersion = 2

    static var displayName: String { active.displayName }
    /// The company whose API terms apply.
    static var company: String { active.company }

    var displayName: String {
        switch self {
        case .gemini: "Google Gemini"
        case .anthropic: "Anthropic Claude"
        }
    }

    var company: String {
        switch self {
        case .gemini: "Google"
        case .anthropic: "Anthropic"
        }
    }

    /// What has to have been allowed for a feature. A feature asks again
    /// when the processor changes, or when what it sends grows (Coach 2:
    /// sleep, heart, stress, weight, drinks and the 30-day series).
    static func consentVersion(for feature: AIFeature) -> Int {
        let scope = switch feature {
        case .coach: 2
        case .photo, .chef: 1
        }
        // Processor 1's consents were stored as 1 (photo, Chef) and 2 (Coach);
        // a new processor moves every feature to a new range.
        return (processorVersion - 1) * 100 + scope
    }
}

/// The features that send something off the iPhone.
nonisolated enum AIFeature: String, CaseIterable, Sendable {
    case coach, photo, chef
}

/// Consent for third-party AI (App Store 5.1.2(i)): asked once per feature
/// before the first use, revocable in Privacy and data. Valid only for the
/// processor it was given for.
nonisolated enum AIConsentRules {
    static func key(_ feature: AIFeature) -> String { "aiConsent.\(feature.rawValue)" }

    /// Granted when the stored version is the current processor's.
    static func isGranted(storedVersion: Int, current: Int) -> Bool {
        storedVersion > 0 && storedVersion == current
    }
}
