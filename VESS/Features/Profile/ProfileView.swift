import SwiftUI

/// You (11): who you are, your weight from Apple Health or your profile,
/// daily goals and preferences, and the settings screens (E01–E10).
struct ProfileView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.default
    @State private var showError = false
    @State private var confirmCycleOff = false
    @State private var confirmCycleDelete = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            if let profile = store.profile {
                ScrollView {
                    VStack(alignment: .leading, spacing: VESSSpacing.section) {
                        header(profile)
                        ProfileWeightCard(profile: profile, snapshot: health.state.snapshot, now: AppClock.now, calendar: calendar)
                        goals(profile)
                        preferences(profile)
                        more
                    }
                    .padding(.horizontal, VESSSpacing.screenInset)
                    .padding(.top, VESSSpacing.md)
                    .padding(.bottom, VESSSpacing.huge)
                }
                .vessScreenBackground()
                .toolbar(.hidden, for: .navigationBar)
                .profileDestinations()
                .vessErrorAlert(isPresented: $showError)
            }
        }
    }

    private func header(_ profile: UserProfile) -> some View {
        HStack(spacing: VESSSpacing.md) {
            Text(verbatim: String(profile.name.prefix(1)).uppercased())
                .vessTextStyle(.titleL)
                .foregroundStyle(VESSColor.text)
                .frame(width: 56, height: 56)
                .background(VESSColor.fill, in: Circle())
                .overlay(Circle().strokeBorder(VESSColor.divider))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                Text(profile.name.isEmpty ? String(localized: "You") : profile.name)
                    .vessTextStyle(.titleL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text("\(Text(profile.goal.shortTitle)) · \(Text(profile.dietTitle)) · \(VESSFormat.calories(profile.nutritionTargets.calories)) kcal")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("you.header")
    }

    private func goals(_ profile: UserProfile) -> some View {
        let targets = profile.nutritionTargets
        return VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            VESSSectionHeader(title: "Daily goals")
            VESSRowGroup {
                link(.goals, icon: "flame", title: "Energy", value: Text("\(VESSFormat.calories(targets.calories)) kcal"))
                link(.goals, icon: "fish", title: "Protein", value: Text("\(VESSFormat.grams(targets.proteinGrams)) g"))
                link(.goals, icon: "drop", title: "Water", value: Text("\(VESSFormat.liters(fromMilliliters: profile.waterTargetMilliliters)) L"))
                link(.goals, icon: "figure.walk", title: "Steps", value: Text(VESSFormat.steps(Double(profile.dailyStepsTarget))))
            }
            .vessHairlineBottom()
        }
    }

    private func preferences(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            VESSSectionHeader(title: "Preferences")
            VESSRowGroup {
                link(.nutrition, title: "Diet", value: Text(profile.dietTitle))
                link(.settings, title: "Appearance", value: Text(appearance.title))
                link(.appleHealth, title: "Apple Health", value: Text(health.state.statusTitle))
                ProfileToggleRow(
                    title: Text("Cycle tracking"),
                    subtitle: Text("Log periods and see an estimate. Stays on this iPhone."),
                    isOn: Binding(get: { profile.isCycleTrackingOn }, set: { setCycleTracking($0, profile: profile) })
                )
                .accessibilityIdentifier("you.cycleTracking")
                .confirmationDialog("Turn off cycle tracking?", isPresented: $confirmCycleOff, titleVisibility: .visible) {
                    Button("Keep data on this iPhone") { saveCycleTracking(false) }
                        .keyboardShortcut(.defaultAction)
                    Button("Delete cycle data", role: .destructive) { confirmCycleDelete = true }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Kept data stays hidden and comes back when you turn tracking on again.")
                }
                .alert("Delete cycle data?", isPresented: $confirmCycleDelete) {
                    Button("Delete", role: .destructive, action: deleteCycleData)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Every logged cycle day will be removed from this iPhone. This can't be undone.")
                }
            }
            .vessHairlineBottom()
        }
    }

    /// Switching off with logged days asks first: keep them (hidden, and
    /// restored when switched on again) or delete them after a second confirm.
    private func setCycleTracking(_ isOn: Bool, profile: UserProfile) {
        if !isOn, !store.cycleDays.isEmpty {
            confirmCycleOff = true
            return
        }
        saveCycleTracking(isOn)
    }

    private func saveCycleTracking(_ isOn: Bool) {
        guard var updated = store.profile else { return }
        updated.cycleTrackingEnabled = isOn
        do {
            try store.saveProfile(updated)
        } catch {
            showError = true
        }
    }

    private func deleteCycleData() {
        do {
            try store.deleteCycleData()
            saveCycleTracking(false)
        } catch {
            showError = true
        }
    }

    private var more: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            VESSSectionHeader(title: "More")
            VESSRowGroup {
                link(.body, title: "Body")
                link(.supplements, title: "Supplements")
                link(.notifications, title: "Notifications")
                link(.privacy, title: "Privacy and data")
                link(.help, title: "Help")
                #if DEBUG
                link(.vessPlus, title: "VESS+ (demo)")
                #endif
            }
            .vessHairlineBottom()
        }
    }

    private func link(_ route: ProfileRoute, icon: String? = nil, title: LocalizedStringResource, value: Text? = nil) -> some View {
        NavigationLink(value: route) {
            VESSListRow(systemImage: icon, title: Text(title), value: value)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Routes

/// The You screens, pushed by value on the You stack.
enum ProfileRoute: Hashable {
    case goals, body, nutrition, supplements, appleHealth, notifications, privacy, settings, help
    case helpArticle(HelpArticle)
    #if DEBUG
    case vessPlus
    #endif
}

extension View {
    func profileDestinations() -> some View {
        navigationDestination(for: ProfileRoute.self) { route in
            switch route {
            case .goals: GoalsView()
            case .body: BodyView()
            case .nutrition: NutritionPreferencesView()
            case .supplements: SupplementsView()
            case .appleHealth: AppleHealthView()
            case .notifications: NotificationsView()
            case .privacy: PrivacyView()
            case .settings: SettingsView()
            case .help: HelpView()
            case .helpArticle(let article): HelpArticleView(article: article)
            #if DEBUG
            case .vessPlus: VESSPlusView()
            #endif
            }
        }
    }
}

// MARK: - Weight card

/// "78.4 kg · weighed this morning" and the last 12 weeks. Facts only: the
/// change over the period, no verdict and no target range (not defined yet).
struct ProfileWeightCard: View {
    let profile: UserProfile
    let snapshot: HealthSnapshot?
    let now: Date
    let calendar: Calendar

    var body: some View {
        let weights = snapshot?.weights ?? []
        let latest = snapshot?.latestWeight

        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Weight")
            VESSMetric(
                value: Text(verbatim: VESSFormat.quantity(latest?.kilograms ?? profile.weightKilograms)),
                context: caption(latest),
                style: .displayL,
                contextStyle: .bodyM
            )
            .foregroundStyle(VESSColor.text)
            .accessibilityElement(children: .combine)
            if weights.count >= 2, let first = weights.first, let last = weights.last {
                ProfileWeightChart(weights: weights)
                changeText(from: first, to: last)
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
    }

    private func caption(_ latest: BodyMassSample?) -> Text {
        guard let latest else { return Text("kg · from your profile") }
        if calendar.isDate(latest.measuredAt, inSameDayAs: now) {
            return calendar.component(.hour, from: latest.measuredAt) < 12
                ? Text("kg · weighed this morning")
                : Text("kg · weighed today")
        }
        return Text("kg · \(latest.measuredAt, format: .dateTime.day().month(.abbreviated)), Apple Health")
    }

    /// "−0.6 kg in 12 weeks".
    private func changeText(from first: BodyMassSample, to last: BodyMassSample) -> Text {
        let change = last.kilograms - first.kilograms
        let weeks = max(1, Int((last.measuredAt.timeIntervalSince(first.measuredAt) / (7 * 86_400)).rounded()))
        let value = change.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
        return Text("\(value) kg in ^[\(weeks) week](inflect: true)")
    }
}

/// The weight line over the last 12 weeks, with month labels. Decorative
/// for VoiceOver; the card states the change.
private struct ProfileWeightChart: View {
    let weights: [BodyMassSample]

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 110
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        let values = weights.map(\.kilograms)
        let low = (values.min() ?? 0) - 0.5
        let high = (values.max() ?? 0) + 0.5
        let start = weights.first?.measuredAt ?? .now
        let span = max((weights.last?.measuredAt ?? .now).timeIntervalSince(start), 1)

        VStack(spacing: VESSSpacing.xs) {
            GeometryReader { proxy in
                let points = weights.map { sample in
                    CGPoint(
                        x: proxy.size.width * sample.measuredAt.timeIntervalSince(start) / span,
                        y: proxy.size.height * (1 - (sample.kilograms - low) / max(high - low, 0.1))
                    )
                }
                // Draws left to right (MOTION.md); the end dot follows.
                Path { path in
                    path.addLines(points)
                }
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(VESSColor.text, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(VESSColor.text)
                        .frame(width: 10, height: 10)
                        .position(last)
                        .opacity(drawn ? 1 : 0)
                }
            }
            .frame(height: height)
            .onAppear {
                withAnimation(reduceMotion ? nil : VESSMotion.chart) { drawn = true }
            }
            HStack {
                Text(weights.first?.measuredAt ?? .now, format: .dateTime.month(.abbreviated))
                Spacer()
                Text(weights.last?.measuredAt ?? .now, format: .dateTime.month(.abbreviated))
            }
            .vessTextStyle(.caption)
            .foregroundStyle(VESSColor.tertiaryText)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shared rows

/// A hairline row with a checkmark when selected (Direction, Diet, Appearance).
struct ProfileCheckRow: View {
    let title: Text
    var subtitle: Text?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VESSRow(title: title, subtitle: subtitle) { EmptyView() } trailing: {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(VESSColor.text)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A hairline row with a switch.
struct ProfileToggleRow: View {
    let title: Text
    var subtitle: Text?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                title
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.text)
                subtitle?
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.vess)
        .padding(.vertical, VESSSpacing.sm)
        .frame(minHeight: VESSSize.rowHeight)
    }
}

/// The editorial line and optional intro at the top of each You screen.
struct ProfileIntro: View {
    let title: LocalizedStringResource
    var text: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            Text(title)
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let text {
                Text(text)
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The scroll page every You destination uses.
struct ProfilePage<Content: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                content
            }
            // Full width, so short pages (Help articles) aren't centred.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground()
        .vessDetailTitle(title)
        .toolbar(.hidden, for: .tabBar)
    }
}

// MARK: - Display

extension WellnessGoal {
    /// "Maintaining" in the You header.
    var shortTitle: LocalizedStringResource {
        switch self {
        case .loseWeight: "Losing weight"
        case .maintainWeight: "Maintaining"
        case .gainWeight: "Gaining weight"
        default: title
        }
    }
}

extension UserProfile {
    /// "Pescatarian", "No restrictions", "Vegetarian".
    var dietTitle: LocalizedStringResource {
        switch dietaryPreference {
        case .everything: "No restrictions"
        case .custom: customDietDescription.map { LocalizedStringResource(stringLiteral: $0) } ?? dietaryPreference.title
        default: dietaryPreference.title
        }
    }
}

extension HealthSyncState {
    /// "Connected", "Not connected"…
    var statusTitle: LocalizedStringResource {
        switch self {
        case .notConnected: "Not connected"
        case .nothingShared: "Nothing shared"
        case .syncing: "Syncing…"
        case .available: "Connected"
        case .failed: "Couldn't sync"
        }
    }
}

#Preview {
    ProfileView()
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
