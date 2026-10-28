import SwiftUI

/// 12: Coach. A calm chat about the user's own logs. The conversation stays
/// on this iPhone; each question goes to the server once, with a summary
/// (see "What Coach sees"), after a one-time consent and with an account.
struct CoachView: View {
    @Environment(LocalStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(AIConsentStore.self) private var consent
    @Environment(HealthDataStore.self) private var health
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(CoachSettings.shareCycleKey) private var shareCycle = false
    @AppStorage("coach.remaining") private var remaining = -1
    @AppStorage("coach.remainingDay") private var remainingDay = ""
    /// Moves the prompt chips on each time Coach opens.
    @AppStorage("coach.promptRotation") private var promptRotation = 0

    @State private var draft = ""
    @State private var isSending = false
    @State private var failure: BackendError?
    @State private var pendingQuestion: String?
    @State private var showConsent = false
    @State private var showSettings = false
    @State private var showSignIn = false
    /// A chart in an answer that was tapped: its metric's screen.
    @State private var openChart: CoachChartRequest.Metric?
    @Environment(\.vessOpenAdd) private var openAdd
    @FocusState private var isComposerFocused: Bool

    private let calendar = Calendar.current


    var body: some View {
        let messages = store.coachMessages

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    Text(greeting)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(messages) { message in
                        bubble(message)
                            .id(message.id)
                            .transition(.opacity)
                    }

                    if isSending {
                        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                            CoachLabel()
                            CoachTypingIndicator()
                        }
                        .transition(.opacity)
                        .accessibilityIdentifier("coach.thinking")
                    }

                    if let failure {
                        failureRow(failure)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) {
                // A new answer is read from its start; a question goes to the bottom.
                withAnimation(reduceMotion ? nil : VESSMotion.selection) {
                    if let last = messages.last, last.role == .assistant {
                        proxy.scrollTo(last.id, anchor: .top)
                    } else {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: isSending) {
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        // Messages fade out at the nav bar instead of running under COACH.
        .vessFadeUnderNavBar()
        .safeAreaInset(edge: .bottom, spacing: 0) { composer(isEmpty: messages.isEmpty) }
        .vessScreenBackground(.fuel, clipsUnderBar: false)
        .vessDetailTitle("Coach")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Coach settings")
                .accessibilityIdentifier("coach.settings")
            }
        }
        .onAppear { promptRotation += 1 }
        .sheet(isPresented: $showSettings) { CoachSettingsSheet() }
        .navigationDestination(item: $openChart) { metric in
            chartDetail(metric)
        }
        .sheet(isPresented: $showSignIn) { AISignInSheet() }
        .vessAIConsent(.coach, isPresented: $showConsent) {
            if let question = pendingQuestion { send(question) }
        }
    }

    // MARK: Messages

    @ViewBuilder
    private func chartDetail(_ metric: CoachChartRequest.Metric) -> some View {
        switch metric {
        case .steps: StepsDetailView(day: AppClock.now)
        case .energy: EnergyDetailView()
        case .protein, .carbs, .fat, .fiber: MacrosDetailView()
        case .water, .caffeine: CaffeineView(day: AppClock.now)
        case .sleep: SleepView()
        case .weight, .bmi: BodyView()
        case .restingHeartRate, .hrv: HeartView()
        case .activeEnergy, .workouts: ActivityView()
        case .sugar: MacrosDetailView()
        case .stress: StressView()
        case .habits: HabitsView()
        case .supplements: SupplementsView()
        }
    }

    @ViewBuilder
    private func bubble(_ message: CoachMessage) -> some View {
        switch message.role {
        case .user:
            Text(verbatim: message.text)
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, VESSSpacing.md)
                .padding(.vertical, VESSSpacing.sm)
                .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, VESSSpacing.huge)
                .accessibilityLabel(Text("You: \(message.text)"))
        case .assistant:
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                CoachLabel()
                CoachAnswer(text: message.text) { metric in
                    if metric == .water { openAdd(.drink) } else { openChart = metric }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func failureRow(_ error: BackendError) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text(error == .dailyLimit ? "That's today's free Coach questions. Back tomorrow." : error.message)
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.warningText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coach.failure")
            switch error {
            case .offline, .upstream, .server, .invalidResponse, .badRequest:
                Button("Try again", action: retry)
                    .buttonStyle(.vessQuick)
                    .accessibilityIdentifier("coach.retry")
            case .notSignedIn:
                Button("Sign in") { showSignIn = true }
                    .buttonStyle(.vessQuick)
            case .dailyLimit, .notConfigured, .authRejected:
                EmptyView()
            }
        }
    }

    // MARK: Composer

    private func composer(isEmpty: Bool) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            // Three prompts from today, when empty and after each answer.
            if account.isSignedIn, !isSending, isEmpty || store.coachMessages.last?.role == .assistant {
                VESSBleedingRow {
                    HStack(spacing: VESSSpacing.xs) {
                        ForEach(CoachPrompts.today(store: store, health: health.state.snapshot, now: AppClock.now, calendar: calendar,
                                                   rotation: promptRotation + store.coachMessages.count / 2), id: \.self) { prompt in
                            Button(prompt) { ask(prompt) }
                                .buttonStyle(.vessQuick)
                        }
                    }
                }
                .transition(.opacity)
            }
            if account.isSignedIn {
                HStack(alignment: .bottom, spacing: VESSSpacing.sm) {
                    TextField("Ask Coach", text: $draft, prompt: Text("Ask Coach").foregroundStyle(VESSColor.tertiaryText), axis: .vertical)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .lineLimit(1...5)
                        .focused($isComposerFocused)
                        .submitLabel(.send)
                        // Multi-line fields don't submit: Return sends instead
                        // of starting a new line.
                        .onChange(of: draft) { _, text in
                            guard text.hasSuffix("\n") else { return }
                            draft = String(text.dropLast())
                            ask(draft)
                        }
                        .padding(.horizontal, VESSSpacing.md)
                        .padding(.vertical, VESSSpacing.sm)
                        .frame(minHeight: VESSHitTarget.control)
                        .accessibilityIdentifier("coach.input")
                    Button { ask(draft) } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .foregroundStyle(VESSColor.onAccent)
                            .frame(width: 36, height: 36)
                            .background(VESSColor.accentFill, in: Circle())
                            .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmed(draft).isEmpty || isSending)
                    .opacity(trimmed(draft).isEmpty || isSending ? 0.4 : 1)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("coach.send")
                    .padding(.trailing, VESSSpacing.xxs)
                    .padding(.bottom, VESSSpacing.xxs)
                }
                .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.sheet, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: VESSRadius.sheet, style: .continuous).strokeBorder(VESSColor.divider))
            } else {
                Button("Sign in to ask Coach") { showSignIn = true }
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("coach.signIn")
            }
            footer
        }
        .padding(.horizontal, VESSSpacing.screenInset)
        .padding(.top, VESSSpacing.sm)
        .padding(.bottom, VESSSpacing.xs)
        .background(VESSColor.background.ignoresSafeArea(edges: .bottom))
        // The chat fades into the composer instead of meeting it at an edge.
        .background(alignment: .top) {
            LinearGradient(colors: [VESSColor.background.opacity(0), VESSColor.background], startPoint: .top, endPoint: .bottom)
                .frame(height: VESSSpacing.lg)
                .offset(y: -VESSSpacing.lg)
                .allowsHitTesting(false)
        }
    }

    private var footer: some View {
        Group {
            if let left = remainingToday, account.isSignedIn {
                Text("^[\(left) question](inflect: true) left today · \(AIQuotaText.resets(after: AppClock.now)) Coach can make mistakes.")
            } else {
                Text("Coach can make mistakes. Check anything important.")
            }
        }
        .vessTextStyle(.caption)
        .foregroundStyle(VESSColor.tertiaryText)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("coach.footer")
    }

    // MARK: Sending

    private var greeting: String {
        let hello = Greeting.text(for: AppClock.now, name: store.profile?.name ?? "", calendar: calendar)
        return String(localized: "\(hello). What's on your mind?")
    }

    /// From the last answer, while it's still the same (UTC) day on the server.
    private var remainingToday: Int? {
        remaining >= 0 && remainingDay == Self.serverDay(AppClock.now) ? remaining : nil
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Asks for consent first, once; then sends.
    private func ask(_ text: String) {
        let question = trimmed(text)
        guard !question.isEmpty, !isSending else { return }
        guard consent.isGranted(.coach) else {
            pendingQuestion = question
            showConsent = true
            return
        }
        send(question)
    }

    private func send(_ question: String) {
        pendingQuestion = nil
        draft = ""
        isComposerFocused = false
        let message = CoachMessage(id: UUID(), role: .user, text: question, createdAt: AppClock.now)
        do {
            try store.add(message)
        } catch {
            failure = .invalidResponse
            return
        }
        request()
    }

    /// Sends the conversation as it is (ending with the last question).
    private func retry() {
        request()
    }

    private func request() {
        guard let context = CoachContextAssembler.context(
            store: store, health: health.state.snapshot, shareCycle: shareCycle, now: AppClock.now, calendar: calendar
        ) else { return }
        let body = CoachRequest.body(history: store.coachMessages, context: context, locale: CoachRequest.locale)
        failure = nil
        isSending = true
        Task {
            do {
                let reply: CoachReply = try await account.callFunction("coach", json: body)
                // The answer fades in (at once with Reduce Motion).
                try withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                    try store.add(CoachMessage(id: UUID(), role: .assistant, text: reply.reply, createdAt: AppClock.now))
                }
                if let left = reply.remaining { setRemaining(left) }
            } catch {
                let backend = BackendError.from(error)
                if backend == .dailyLimit { setRemaining(0) }
                failure = backend
            }
            isSending = false
        }
    }

    private func setRemaining(_ value: Int) {
        remaining = value
        remainingDay = Self.serverDay(AppClock.now)
    }

    /// The server counts uses per UTC day.
    static func serverDay(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// An answer in blocks: paragraphs with bold and italic, lists with a
/// hanging bullet. Raw Markdown markers never show.
struct CoachAnswer: View {
    let text: String
    var onOpenChart: (CoachChartRequest.Metric) -> Void = { _ in }

    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            ForEach(Array(CoachReplyFormat.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let paragraph):
                    styled(Text(paragraph))
                case .list(let items):
                    VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                        ForEach(items.indices, id: \.self) { index in
                            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                                Text(verbatim: "•").foregroundStyle(VESSColor.secondaryText)
                                styled(Text(items[index]))
                            }
                        }
                    }
                case .chart(let request):
                    // Drawn from this iPhone's data, never from the answer's numbers.
                    if request.isToday {
                        CoachTodayCard(metric: request.metric) { onOpenChart(request.metric) }
                    } else {
                        let series = CoachChartSeries.make(request, store: store, health: health.state.snapshot, now: AppClock.now, calendar: .current)
                        CoachChartCard(series: series) { onOpenChart(request.metric) }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private func styled(_ text: Text) -> some View {
        text
            .vessTextStyle(.bodyM)
            .foregroundStyle(VESSColor.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Three dots while Coach is answering; still with Reduce Motion.
struct CoachTypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: VESSSpacing.xxs + 2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(VESSColor.tertiaryText)
                    .frame(width: 7, height: 7)
                    .phaseAnimator(reduceMotion ? [1.0] : [0.3, 1.0]) { dot, opacity in
                        dot.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.5).delay(Double(index) * 0.15) }
            }
        }
        .frame(minHeight: VESSHitTarget.minimum / 2)
        .accessibilityElement()
        .accessibilityLabel("Coach is answering")
    }
}

/// Three questions for today: "What can I cook tonight?" first while
/// dinner isn't logged after 15:00, then questions about the metrics that
/// have data today, rotating each time Coach opens and after each answer.
enum CoachPrompts {
    /// A metric with data today and its question.
    nonisolated struct Candidate: Equatable, Sendable {
        let metric: CoachChartRequest.Metric
        let question: String
    }

    @MainActor
    static func today(store: LocalStore, health: HealthSnapshot?, now: Date, calendar: Calendar, rotation: Int) -> [String] {
        let hour = calendar.component(.hour, from: now)
        let entries = store.foodEntries(on: now, calendar: calendar)
        let drinks = store.hydrationLogs(on: now, calendar: calendar)
        let food = entries.map(\.nutrition).total
        var has: Set<CoachChartRequest.Metric> = []
        if !entries.isEmpty { has.formUnion([.energy, .protein, .carbs]) }
        if food.fiberGrams != nil { has.insert(.fiber) }
        if !drinks.isEmpty { has.insert(.water) }
        if CaffeineModel.total(drinks, on: now, calendar: calendar) >= 1 { has.insert(.caffeine) }
        if !store.habits.isEmpty { has.insert(.habits) }
        if !store.supplements.isEmpty { has.insert(.supplements) }
        if let health {
            if health.steps > 0 { has.insert(.steps) }
            if (health.activeEnergyKilocalories ?? 0) > 0 { has.insert(.activeEnergy) }
            let nights = SleepRules.nights(health.sleep, calendar: calendar)
            if SleepRules.lastNight(nights, now: now, calendar: calendar) != nil { has.insert(.sleep) }
            if HeartRules.value(on: now, health.restingHeartRate, calendar: calendar) != nil { has.insert(.restingHeartRate) }
            if HeartRules.value(on: now, StressRules.overnightHRV(health.heartRateVariability, calendar: calendar), calendar: calendar) != nil {
                has.formUnion([.hrv, .stress])
            }
            if health.latestWeight.map({ calendar.isDate($0.measuredAt, inSameDayAs: now) }) == true { has.insert(.weight) }
        }
        if (store.workouts + (health?.workouts ?? [])).contains(where: { $0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } == true }) {
            has.insert(.workouts)
        }
        let first = hour >= 15 && entries.entries(for: .dinner).isEmpty ? [String(localized: "What can I cook tonight?")] : []
        return pick(first: first, candidates: candidates.filter { has.contains($0.metric) }, rotation: rotation)
    }

    /// `first`, then candidates from `rotation` on (wrapping), three in all;
    /// general questions fill in when there are fewer.
    nonisolated static func pick(first: [String], candidates: [Candidate], rotation: Int, count: Int = 3) -> [String] {
        var prompts = first
        if !candidates.isEmpty {
            let start = ((rotation % candidates.count) + candidates.count) % candidates.count
            for offset in 0..<candidates.count where prompts.count < count {
                let question = candidates[(start + offset) % candidates.count].question
                if !prompts.contains(question) { prompts.append(question) }
            }
        }
        for fallback in [String(localized: "How's my protein this week?"), String(localized: "What can I cook tonight?"), String(localized: "How's my water today?")]
        where prompts.count < count && !prompts.contains(fallback) {
            prompts.append(fallback)
        }
        return Array(prompts.prefix(count))
    }

    /// One question per metric, in the order they rotate.
    nonisolated static var candidates: [Candidate] {
        [
            .init(metric: .sleep, question: String(localized: "How did I sleep?")),
            .init(metric: .protein, question: String(localized: "How's my protein this week?")),
            .init(metric: .steps, question: String(localized: "How many steps did I do this week?")),
            .init(metric: .water, question: String(localized: "How's my water today?")),
            .init(metric: .caffeine, question: String(localized: "How much caffeine have I had today?")),
            .init(metric: .restingHeartRate, question: String(localized: "How's my resting heart rate?")),
            .init(metric: .energy, question: String(localized: "How's my energy this week?")),
            .init(metric: .stress, question: String(localized: "How was my stress today?")),
            .init(metric: .habits, question: String(localized: "How are my habits going?")),
            .init(metric: .fiber, question: String(localized: "Am I getting enough fibre?")),
            .init(metric: .activeEnergy, question: String(localized: "How active was I this week?")),
            .init(metric: .hrv, question: String(localized: "What does my HRV say?")),
            .init(metric: .carbs, question: String(localized: "How are my carbs today?")),
            .init(metric: .workouts, question: String(localized: "How were my workouts this week?")),
            .init(metric: .weight, question: String(localized: "How's my weight trending?")),
            .init(metric: .supplements, question: String(localized: "Did I take my supplements?")),
        ]
    }
}

/// "∿ COACH" above an answer.
private struct CoachLabel: View {
    var body: some View {
        Label {
            Text("Coach")
        } icon: {
            Image(systemName: "waveform.path.ecg")
        }
        .vessTextStyle(.labelCaps)
        .foregroundStyle(VESSColor.secondaryText)
        .accessibilityHidden(true)
    }
}

enum CoachSettings {
    static let shareCycleKey = "coach.shareCycle"
}

/// What Coach sees, sharing cycle data, and Clear conversation.
struct CoachSettingsSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @Environment(\.vessHaptics) private var haptics
    @Environment(\.dismiss) private var dismiss

    @AppStorage(CoachSettings.shareCycleKey) private var shareCycle = false
    @State private var confirmClear = false
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    VESSRowGroup {
                        NavigationLink {
                            CoachContextView(shareCycle: shareCycle)
                        } label: {
                            VESSListRow(title: Text("What Coach sees"), subtitle: Text("The summary sent with each question"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("coach.whatCoachSees")
                        if store.profile?.isCycleTrackingOn == true {
                            ProfileToggleRow(
                                title: Text("Share cycle with Coach"),
                                subtitle: Text("Cycle day and the next estimated window. Off unless you turn it on."),
                                isOn: $shareCycle
                            )
                            .accessibilityIdentifier("coach.shareCycle")
                        }
                    }
                    .vessHairlineBottom()

                    Text("Questions go to \(AIProcessor.displayName) through VESS's server. VESS doesn't store them. \(AIProcessor.company) processes them under its API terms. The conversation is kept only on this iPhone.")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Clear conversation", role: .destructive) { confirmClear = true }
                        .buttonStyle(.vessSecondary)
                        .foregroundStyle(VESSColor.criticalText)
                        .disabled(store.coachMessages.isEmpty)
                        .accessibilityIdentifier("coach.clear")
                        .confirmationDialog("Clear the conversation?", isPresented: $confirmClear, titleVisibility: .visible) {
                            Button("Clear conversation", role: .destructive, action: clear)
                        } message: {
                            Text("Every message is removed from this iPhone.")
                        }
                }
                .padding(VESSSpacing.screenInset)
            }
            .background(VESSColor.card)
            .vessDetailTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .vessErrorAlert(isPresented: $showError)
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    private func clear() {
        do {
            try store.deleteCoachMessages()
            haptics.play(.warning)
        } catch {
            showError = true
        }
    }
}

/// Exactly the JSON sent with the next question, indented.
struct CoachContextView: View {
    let shareCycle: Bool

    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    var body: some View {
        let context = CoachContextAssembler.context(store: store, health: health.state.snapshot, shareCycle: shareCycle, now: AppClock.now, calendar: .current)
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                Text("This summary goes with each question, and nothing else from your log. Numbers are rounded; there are no IDs.")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: context.map(CoachContextBuilder.readableJSON) ?? "{}")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(VESSColor.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(VESSSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
                    .accessibilityIdentifier("coach.contextJSON")
            }
            .padding(VESSSpacing.screenInset)
        }
        .background(VESSColor.card)
        .vessDetailTitle("What Coach sees")
    }
}

/// Coach and photos ask for an account in place; closes once signed in.
struct AISignInSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    ProfileIntro(title: "An account for AI features.", text: "Only for Coach, photo estimates and AI Chef. Your log stays on this iPhone.")
                    AccountSignInForm()
                }
                .padding(VESSSpacing.screenInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(VESSColor.card)
            .vessDetailTitle("Sign in")
            .vessKeyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onChange(of: account.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }
}
