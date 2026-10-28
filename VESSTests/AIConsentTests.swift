import Foundation
import Testing
@testable import VESS

@MainActor
@Suite("AI consent")
struct AIConsentTests {
    private func freshDefaults() -> UserDefaults {
        let name = "test.consent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Nothing is allowed until asked; each feature is separate")
    func perFeature() {
        let store = AIConsentStore(defaults: freshDefaults())
        #expect(!store.isGranted(.coach) && !store.isGranted(.photo))
        store.grant(.coach)
        #expect(store.isGranted(.coach) && !store.isGranted(.photo))
    }

    @Test("Revoking in Privacy turns it off, and it stays off after relaunch")
    func revoke() {
        let defaults = freshDefaults()
        let store = AIConsentStore(defaults: defaults)
        store.grant(.photo)
        store.revoke(.photo)
        #expect(!store.isGranted(.photo))
        #expect(!AIConsentStore(defaults: defaults).isGranted(.photo))
        store.grant(.coach)
        #expect(AIConsentStore(defaults: defaults).isGranted(.coach), "Kept across launches")
    }

    @Test("Consent is for one processor: a new consent version asks again")
    func versionBump() {
        #expect(AIConsentRules.isGranted(storedVersion: 1, current: 1))
        #expect(!AIConsentRules.isGranted(storedVersion: 1, current: 2), "Switching provider asks again")
        #expect(!AIConsentRules.isGranted(storedVersion: 0, current: 1))
        #expect(AIConsentRules.key(.coach) != AIConsentRules.key(.photo))
    }

    @Test("The processor is named in one place")
    func processorName() {
        #expect(AIProcessor.active == .gemini, "Gemini stays active until the server switches")
        #expect(AIProcessor.displayName == "Google Gemini" && AIProcessor.company == "Google")
        #expect(AIProcessor.anthropic.displayName == "Anthropic Claude" && AIProcessor.anthropic.company == "Anthropic")
    }

    @Test("Coach asks again because it sends more; photo and AI Chef consents stay valid")
    func coachScopeBump() {
        let defaults = freshDefaults()
        // Consents from the previous build were stored as 1.
        AIFeature.allCases.forEach { defaults.set(1, forKey: AIConsentRules.key($0)) }
        let store = AIConsentStore(defaults: defaults)
        #expect(!store.isGranted(.coach))
        #expect(store.isGranted(.photo) && store.isGranted(.chef))
        store.grant(.coach)
        #expect(store.isGranted(.coach))
    }
}
