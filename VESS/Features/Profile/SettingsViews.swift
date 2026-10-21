import SwiftUI
import UniformTypeIdentifiers

// MARK: - E05 Apple Health

/// What VESS reads from Apple Health, read-only. iOS controls access, so the
/// four types are plain rows, not switches.
struct AppleHealthView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    var body: some View {
        let stepsTarget = store.profile?.dailyStepsTarget ?? UserProfile.defaultStepsTarget

        ProfilePage(title: "Apple Health") {
            ProfileIntro(title: "Read-only, on your terms.", text: "VESS reads movement and body data from Apple Health to show it in Activity, Today and You. It never writes to Health.")

            VESSRowGroup {
                VESSListRow(title: Text("Status"), value: Text(health.state.statusTitle), showsChevron: false)
                VESSListRow(
                    title: Text("Last sync"),
                    value: health.state.snapshot.map { Text($0.updatedAt, format: .dateTime.hour().minute()) } ?? Text(verbatim: "—"),
                    showsChevron: false
                )
            }
            .vessHairlineBottom()

            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                VESSSectionHeader(title: "Read from Health")
                VESSRowGroup {
                    VESSListRow(title: Text("Steps"), showsChevron: false)
                    VESSListRow(title: Text("Workouts"), showsChevron: false)
                    VESSListRow(title: Text("Active energy"), showsChevron: false)
                    VESSListRow(title: Text("Weight"), showsChevron: false)
                }
                .vessHairlineBottom()
                ActivityFootnote(text: Text("iOS decides what VESS can read. To change access, open the Health app, tap your profile, then Apps › VESS."))
            }

            switch health.state {
            case .notConnected where health.canConnect:
                Button("Connect Apple Health") { Task { await health.connect(stepsTarget: stepsTarget) } }
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("health.connect")
            case .failed:
                Button("Retry") { Task { await health.refresh(stepsTarget: stepsTarget) } }
                    .buttonStyle(.vessSecondary)
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - E06 Notifications

/// Meal reminders (PRODUCT-LOGIC.md #12) and a link to supplement reminders.
/// Quiet hours are fixed at 22:00–07:00.
struct NotificationsView: View {
    @Environment(LocalStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(\.openURL) private var openURL

    @State private var showDenied = false

    var body: some View {
        let supplementsOn = store.supplements.filter(\.reminderEnabled).count

        ProfilePage(title: "Notifications") {
            ProfileIntro(title: "A nudge, when it helps.")

            VESSRowGroup {
                ProfileToggleRow(
                    title: Text("Meal reminders"),
                    subtitle: Text("30 minutes after a main meal's usual time, only if it isn't logged"),
                    isOn: Binding(get: { reminders.mealRemindersOn }, set: setMealReminders)
                )
                .accessibilityIdentifier("notifications.meals")
                NavigationLink(value: ProfileRoute.supplements) {
                    VESSListRow(title: Text("Supplement reminders"), value: Text("\(supplementsOn) on"))
                }
                .buttonStyle(.plain)
            }
            .vessHairlineBottom()

            if showDenied || (reminders.isDenied && reminders.mealRemindersOn) {
                NotificationsDeniedNote {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }

            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                VESSSectionHeader(title: "Quiet hours")
                VESSRowGroup {
                    VESSListRow(title: Text("From"), value: Self.time(MealReminders.quietStartHour), showsChevron: false)
                    VESSListRow(title: Text("To"), value: Self.time(MealReminders.quietEndHour), showsChevron: false)
                }
                .vessHairlineBottom()
                ActivityFootnote(text: Text("No meal reminders in these hours. Reminders are scheduled on this iPhone; nothing is sent to a server."))
            }
        }
        .task { await reminders.refreshAuthorization() }
    }

    private func setMealReminders(_ on: Bool) {
        guard on else {
            reminders.mealRemindersOn = false
            Task { await reminders.sync(store: store) }
            return
        }
        Task {
            if await reminders.requestPermissionIfNeeded() {
                showDenied = false
                reminders.mealRemindersOn = true
                await reminders.sync(store: store)
            } else {
                showDenied = true
            }
        }
    }

    private static func time(_ hour: Int) -> Text {
        let date = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: hour)) ?? .now
        return Text(date, format: .dateTime.hour().minute())
    }
}

// MARK: - E07 Privacy

/// What VESS stores where, an export of everything, and Delete all data.
struct PrivacyView: View {
    @Environment(LocalStore.self) private var store

    @State private var confirmDelete = false
    @State private var showError = false

    var body: some View {
        let now = AppClock.now
        let export = (try? store.exportData(now: now)).map {
            VESSExportFile(data: $0, name: "VESS-export-\(now.formatted(.iso8601.year().month().day())).json")
        }

        ProfilePage(title: "Privacy") {
            ProfileIntro(title: "Your data stays yours.")

            VESSRowGroup {
                fact("On this iPhone", "Everything you log: meals, drinks, workouts, pantry, plans, supplements and your profile.")
                fact("Open Food Facts", "When you search or scan, the search words or the barcode go to Open Food Facts to find the product. Nothing else is sent.")
                fact("Apple Health", "Read only: steps, workouts, active energy and weight. VESS shows them but doesn't keep a copy.")
                fact("Reminders", "Scheduled on this iPhone, never on a server.")
                fact("Nothing else", "VESS has no account, no analytics and no ads.")
            }
            .vessHairlineBottom()

            if let export {
                ShareLink(item: export, preview: SharePreview(Text("VESS data export"))) {
                    VESSListRow(title: Text("Export my data"), subtitle: Text("Everything above, as a JSON file"))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .vessHairlineBottom()
                .accessibilityIdentifier("privacy.export")
            }

            Button("Delete all data", role: .destructive) { confirmDelete = true }
                .buttonStyle(.vessSecondary)
                .foregroundStyle(VESSColor.criticalText)
                .accessibilityIdentifier("privacy.delete")
                .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete all data", role: .destructive, action: deleteAll)
                } message: {
                    Text("Your profile, meals, drinks, workouts, pantry, plans and supplements will be removed from this iPhone. This can't be undone.")
                }
        }
        .vessErrorAlert(isPresented: $showError, retry: deleteAll)
    }

    private func fact(_ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        VESSRow(title: Text(title), subtitle: Text(detail), subtitleLineLimit: 4) { EmptyView() } trailing: { EmptyView() }
            .accessibilityElement(children: .combine)
    }

    private func deleteAll() {
        do {
            try store.deleteAllData()
        } catch {
            showError = true
        }
    }
}

/// The export, written to a temporary file when shared.
nonisolated struct VESSExportFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let url = URL.temporaryDirectory.appending(path: file.name)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

// MARK: - E09 Settings

/// Appearance, plus what follows the iPhone's own settings.
struct SettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.default
    @Environment(\.openURL) private var openURL

    var body: some View {
        let calendar = Calendar.current
        let weekStart = calendar.standaloneWeekdaySymbols[(calendar.firstWeekday - 1) % 7]
        let language = Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English"

        ProfilePage(title: "Settings") {
            ProfileIntro(title: "Make VESS feel familiar.")

            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                VESSSectionHeader(title: "Appearance")
                VESSRowGroup {
                    ForEach(AppAppearance.allCases, id: \.self) { option in
                        ProfileCheckRow(title: Text(option.title), isSelected: appearance == option) { appearance = option }
                    }
                }
                .vessHairlineBottom()
                .accessibilityIdentifier("you.appearance")
            }

            VESSRowGroup {
                VESSListRow(title: Text("Week starts on"), value: Text(verbatim: weekStart), showsChevron: false)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    VESSListRow(title: Text("Language"), value: Text(verbatim: language))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Settings")
            }
            .vessHairlineBottom()

            ActivityFootnote(text: Text("Week start and language follow your iPhone's settings. Units are metric."))
        }
    }
}

// MARK: - E10 Help

enum HelpArticle: String, Hashable, CaseIterable {
    case gettingStarted, estimates, planning, appleHealth

    var title: LocalizedStringResource {
        switch self {
        case .gettingStarted: "Getting started"
        case .estimates: "How estimates work"
        case .planning: "Plan, grocery and pantry"
        case .appleHealth: "Apple Health"
        }
    }

    var paragraphs: [LocalizedStringResource] {
        switch self {
        case .gettingStarted: [
            "Tap + to log a meal or a drink: search, scan a barcode, or enter it yourself. Today shows how your day is going against your own targets.",
            "Fuel is a summary of what you've logged today, from 0 to 100. It only rises as you log, and it isn't a health measurement.",
            "You can change your targets, diet and what to avoid at any time under You.",
        ]
        case .estimates: [
            "Foods from the built-in list show typical values. Products from Open Food Facts are community data, and VESS says so. What you enter yourself is used as you entered it.",
            "Energy for workouts you enter is estimated from type, duration, effort and your weight, so it's shown with ≈. Recorded workouts use Apple Health's measurement.",
            "VESS never estimates steps.",
        ]
        case .planning: [
            "Plan your week's meals from saved foods and meals. Suggestions follow your diet and what you avoid, and prefer what's in your pantry and expires soon.",
            "The grocery list is built from the meals you've planned, minus what you already have. Checking an item doesn't store it; Done shopping moves checked items into your pantry.",
        ]
        case .appleHealth: [
            "VESS reads steps, workouts, active energy and weight from Apple Health. It never writes to Health.",
            "iOS decides what VESS can read. To change access, open the Health app, tap your profile, then Apps › VESS.",
        ]
        }
    }
}

struct HelpView: View {
    var body: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"

        ProfilePage(title: "Help") {
            ProfileIntro(title: "A little clarity.")
            VESSRowGroup {
                ForEach(HelpArticle.allCases, id: \.self) { article in
                    NavigationLink(value: ProfileRoute.helpArticle(article)) {
                        VESSListRow(title: Text(article.title))
                    }
                    .buttonStyle(.plain)
                }
            }
            .vessHairlineBottom()
            ActivityFootnote(text: Text("VESS \(version) (\(build))"))
        }
    }
}

struct HelpArticleView: View {
    let article: HelpArticle

    var body: some View {
        ProfilePage(title: "Help") {
            Text(article.title)
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - E08 VESS+ (DEBUG only)

#if DEBUG
/// A static design for review. Nothing is sold: StoreKit isn't built, and
/// Release builds have no row for this screen.
struct VESSPlusView: View {
    var body: some View {
        ProfilePage(title: "VESS+") {
            ProfileIntro(title: "More room for your journal.", text: "Annual plan · renews 14 March 2027")
            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                Text(39.99, format: .currency(code: "EUR"))
                    .vessTextStyle(.displayL)
                    .foregroundStyle(VESSColor.text)
                Text("/ year")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                VESSSectionHeader(title: "Included")
                VESSRowGroup {
                    ForEach(["Meal photo estimates", "Weekly plan suggestions", "Grocery list and pantry", "Insights history"], id: \.self) { feature in
                        VESSRow(title: Text(verbatim: feature)) { EmptyView() } trailing: {
                            Image(systemName: "checkmark")
                                .foregroundStyle(VESSColor.secondaryText)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .vessHairlineBottom()
            }
            Button("Manage subscription") {}
                .buttonStyle(.vessPrimary)
                .disabled(true)
            Button("Restore purchases") {}
                .buttonStyle(.vessSecondary)
                .disabled(true)
            ActivityFootnote(text: Text(verbatim: "Demo screen for review (DEBUG only). Nothing is sold in this build."))
        }
    }
}
#endif
