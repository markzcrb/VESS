import Foundation

/// Public pages linked from the first screen, the paywall and Privacy.
nonisolated enum LegalLinks {
    // TODO(Mark): publish both pages before release; App Review opens them.
    static let terms = URL(string: "https://umeva.app/terms")
    static let privacyPolicy = URL(string: "https://umeva.app/privacy")
    /// Apple's standard licence agreement, the Terms of Use for subscriptions.
    static let appleEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
}
