import Foundation

/// "Delete all data" and "Delete account and all data": the store, every
/// AI consent, every scheduled or delivered reminder, and the profile's
/// iCloud copy. With no profile left, the app starts again at B02.
enum LocalDataWipe {
    static func run(store: LocalStore, consent: AIConsentStore, reminders: ReminderService, mirror: ProfileMirror) throws {
        try store.deleteAllData()
        consent.revokeAll()
        reminders.removeAll()
        mirror.clear()
    }
}
