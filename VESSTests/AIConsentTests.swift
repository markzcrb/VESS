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
        #expect(!AIProcessor.displayName.isEmpty && !AIProcessor.company.isEmpty && AIProcessor.consentVersion >= 1)
    }
}
