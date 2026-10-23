import Foundation

/// Who processes Coach questions and food photos, behind VESS's server. The
/// server picks the provider; the app only names it, from here. Switching
/// provider: change these and bump `consentVersion`, so everyone is asked
/// again before anything goes to the new one.
nonisolated enum AIProcessor {
    static let displayName = "Google Gemini"
    /// The company whose API terms apply.
    static let company = "Google"
    static let consentVersion = 1
}

/// The two features that send something off the iPhone.
nonisolated enum AIFeature: String, CaseIterable, Sendable {
    case coach, photo
}

/// Consent for third-party AI (App Store 5.1.2(i)): asked once per feature
/// before the first use, revocable in Privacy and data. Valid only for the
/// processor it was given for.
nonisolated enum AIConsentRules {
    static func key(_ feature: AIFeature) -> String { "aiConsent.\(feature.rawValue)" }

    /// Granted when the stored version is the current processor's.
    static func isGranted(storedVersion: Int, current: Int = AIProcessor.consentVersion) -> Bool {
        storedVersion > 0 && storedVersion == current
    }
}
