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

    @Test("Delete all data revokes every AI consent")
    func revokeAll() {
        let defaults = freshDefaults()
        let store = AIConsentStore(defaults: defaults)
        AIFeature.allCases.forEach(store.grant)
        store.revokeAll()
        #expect(AIFeature.allCases.allSatisfy { !AIConsentStore(defaults: defaults).isGranted($0) })
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
        #expect(AIProcessor.active == .anthropic, "Anthropic Claude, as the server")
        #expect(AIProcessor.displayName == "Anthropic Claude" && AIProcessor.company == "Anthropic")
        #expect(AIProcessor.gemini.displayName == "Google Gemini")
        #expect(AIProcessor.anthropic.displayName == "Anthropic Claude" && AIProcessor.anthropic.company == "Anthropic")
    }

    @Test("The switch to Anthropic asks again for every feature; a new consent is kept")
    func processorSwitch() {
        let defaults = freshDefaults()
        // Consents given for Gemini: photo and Chef as 1, Coach as 2.
        defaults.set(2, forKey: AIConsentRules.key(.coach))
        defaults.set(1, forKey: AIConsentRules.key(.photo))
        defaults.set(1, forKey: AIConsentRules.key(.chef))
        let store = AIConsentStore(defaults: defaults)
        #expect(AIFeature.allCases.allSatisfy { !store.isGranted($0) }, "Asked again, with Anthropic named")
        store.grant(.coach)
        #expect(store.isGranted(.coach) && !store.isGranted(.photo))
    }
}
