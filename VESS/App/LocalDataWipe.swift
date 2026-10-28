import Foundation

/// "Delete all data" and "Delete account and all data": the store, every
/// AI consent and every scheduled or delivered reminder. With no profile
/// left, the app starts again at B02.
enum LocalDataWipe {
    static func run(store: LocalStore, consent: AIConsentStore, reminders: ReminderService) throws {
        try store.deleteAllData()
        consent.revokeAll()
        reminders.removeAll()
    }
}
