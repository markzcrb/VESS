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
    private let logger = Logger(subsystem: AppLog.subsystem, category: "Reminders")

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

    /// Whether reminders are already allowed, so P02 can promise the day-5
    /// reminder. VESS doesn't ask for this at purchase.
    var canRemind: Bool {
        [.authorized, .provisional, .ephemeral].contains(authorization)
    }

    /// P02's promise: on day 5 of the VESS+ trial, at 10:00, a reminder that
    /// it ends in two days. Only when reminders are already allowed (the
    /// paywall promises it only then); never asks.
    /// Returns when the reminder is scheduled, or `nil` when it isn't (no
    /// permission, already past, or the system refused it).
    @discardableResult
    func scheduleTrialReminder(trialStartedAt start: Date, quiet: QuietHours = .standard, calendar: Calendar = .current) async -> Date? {
        guard let center else { return nil }
        await refreshAuthorization()
        guard canRemind else { return nil }
        let day5 = calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: start)) ?? start
        // 10:00, or when quiet hours end if they cover it.
        guard let ten = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day5) else { return nil }
        let date = quiet.firstAllowed(atOrAfter: ten, calendar: calendar)
        guard date > AppClock.now else { return nil }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Your UMEVA+ trial ends in 2 days")
        content.body = String(localized: "Nothing to do if you'd like to keep it. To cancel: Settings › Apple Account › Subscriptions.")
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        do {
            try await center.add(UNNotificationRequest(identifier: Self.trialReminderID, content: content,
                                                       trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            return date
        } catch {
            logger.error("Scheduling the trial reminder failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The trial converted or was cancelled: the reminder isn't needed.
    func cancelTrialReminder() {
        center?.removePendingNotificationRequests(withIdentifiers: [Self.trialReminderID])
    }

    static let trialReminderID = "plus.trialEnding"

    /// Replaces VESS's pending reminders with the current plan.
    func sync(store: LocalStore, now: Date = AppClock.now, calendar: Calendar = .current) async {
        guard let center else { return }
        await refreshAuthorization()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter {
            $0.hasPrefix(MealReminders.idPrefix) || $0.hasPrefix(Self.supplementPrefix) || $0.hasPrefix(HabitRules.idPrefix)
        })
        guard [.authorized, .provisional, .ephemeral].contains(authorization) else { return }

        var requests: [UNNotificationRequest] = []
        let quiet = store.profile?.quietHours ?? .standard
        if mealRemindersOn {
            let today = calendar.startOfDay(for: now)
            let historyStart = calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: today) ?? today
            let planEnd = calendar.date(byAdding: .day, value: MealReminders.daysAhead + 1, to: today) ?? today
            let plan = MealReminders.plan(
                history: store.foodEntries(from: historyStart, to: today),
                logged: store.foodEntries(from: today, to: planEnd),
                now: now,
                calendar: calendar,
                quiet: quiet
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
            // A daily time in quiet hours isn't scheduled.
            let at = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: now) ?? now
            guard !quiet.contains(at, calendar: calendar) else { continue }
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
        // Habits: on their days, only while not done, never in quiet hours.
        // Steps come from Apple Health, which isn't read here, so a steps
        // habit's reminder doesn't know today's count.
        let habits = store.habits
        if habits.contains(where: { $0.reminder != nil }) {
            let log = HabitLogLoader.log(
                store: store, health: nil,
                from: HabitRules.week(containing: now, calendar: calendar).first ?? now, through: now, calendar: calendar
            )
            let names = Dictionary(habits.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            requests += HabitRules.reminders(habits, log: log, now: now, calendar: calendar, quiet: quiet).map { reminder in
                let content = UNMutableNotificationContent()
                content.title = names[reminder.habitID] ?? ""
                content.body = String(localized: "A reminder you set. No pressure.")
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
                return UNNotificationRequest(identifier: reminder.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            }
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
