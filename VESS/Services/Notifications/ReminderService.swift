import Foundation
import Observation
import OSLog
import UserNotifications

/// Local reminders: meal reminders (`MealReminders`) and the user's own
/// supplement reminders. Nothing leaves the device. Permission is asked the
/// first time the user turns a reminder on, never earlier.
@Observable
final class ReminderService {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// "Meal reminders" on E06.
    var mealRemindersOn: Bool {
        didSet { defaults.set(mealRemindersOn, forKey: Self.mealsKey) }
    }

    private let center: UNUserNotificationCenter?
    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "VESS", category: "Reminders")

    private static let mealsKey = "reminders.meals"
    static let supplementPrefix = "supplement."

    /// - Parameter center: `nil` for previews and tests: nothing is scheduled.
    init(center: UNUserNotificationCenter? = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        self.mealRemindersOn = defaults.bool(forKey: Self.mealsKey)
    }

    var isDenied: Bool { authorization == .denied }

    func refreshAuthorization() async {
        guard let center else { return }
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Asks once, when the first reminder is turned on. `false` if the user
    /// declined now or earlier; the switch then stays off.
    func requestPermissionIfNeeded() async -> Bool {
        guard let center else { return false }
        await refreshAuthorization()
        switch authorization {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            await refreshAuthorization()
            return granted
        default:
            return false
        }
    }

    /// Replaces VESS's pending reminders with the current plan.
    func sync(store: LocalStore, now: Date = AppClock.now, calendar: Calendar = .current) async {
        guard let center else { return }
        await refreshAuthorization()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            $0.hasPrefix(MealReminders.idPrefix) || $0.hasPrefix(Self.supplementPrefix)
        })
        guard [.authorized, .provisional, .ephemeral].contains(authorization) else { return }

        var requests: [UNNotificationRequest] = []
        if mealRemindersOn {
            let today = calendar.startOfDay(for: now)
            let historyStart = calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: today) ?? today
            let planEnd = calendar.date(byAdding: .day, value: MealReminders.daysAhead + 1, to: today) ?? today
            let plan = MealReminders.plan(
                history: store.foodEntries(from: historyStart, to: today),
                logged: store.foodEntries(from: today, to: planEnd),
                now: now,
                calendar: calendar
            )
            requests += plan.map { reminder in
                let content = UNMutableNotificationContent()
                content.title = String(localized: reminder.meal.title)
                content.body = String(localized: "Nothing logged for \(String(localized: reminder.meal.title).lowercased()) yet. Add it when you're ready.")
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
                return UNNotificationRequest(identifier: reminder.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            }
        }
        for supplement in store.supplements where supplement.reminderEnabled {
            guard let time = supplement.reminderTime else { continue }
            let content = UNMutableNotificationContent()
            content.title = supplement.name
            content.body = String(localized: "A reminder you set for \(supplement.name).")
            let parts = DateComponents(hour: time.hour, minute: time.minute)
            requests.append(UNNotificationRequest(
                identifier: "\(Self.supplementPrefix)\(supplement.id.uuidString)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            ))
        }
        for request in requests {
            do {
                try await center.add(request)
            } catch {
                logger.error("Scheduling a reminder failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
