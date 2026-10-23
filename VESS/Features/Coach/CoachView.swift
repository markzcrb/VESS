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

    @State private var draft = ""
    @State private var isSending = false
    @State private var failure: BackendError?
    @State private var pendingQuestion: String?
    @State private var showConsent = false
    @State private var showSettings = false
    @State private var showSignIn = false
    @FocusState private var isComposerFocused: Bool

    private let calendar = Calendar.current

    private static let suggestions: [LocalizedStringResource] = [
        "How has my protein been this week?",
        "What could I have for dinner?",
        "How's my water today?",
    ]

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
                    }

                    if isSending {
                        CoachLabel()
                        Text("Thinking…")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.tertiaryText)
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
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: isSending) {
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer(isEmpty: messages.isEmpty) }
        .vessScreenBackground(.fuel)
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
        .sheet(isPresented: $showSettings) { CoachSettingsSheet() }
        .sheet(isPresented: $showSignIn) { AISignInSheet() }
        .vessAIConsent(.coach, isPresented: $showConsent) {
            if let question = pendingQuestion { send(question) }
        }
    }

    // MARK: Messages

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
                Text(verbatim: message.text)
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
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
            if isEmpty, account.isSignedIn {
                VESSBleedingRow {
                    HStack(spacing: VESSSpacing.xs) {
                        ForEach(Self.suggestions.indices, id: \.self) { index in
                            Button(String(localized: Self.suggestions[index])) { ask(String(localized: Self.suggestions[index])) }
                                .buttonStyle(.vessQuick)
                                .disabled(isSending)
                        }
                    }
                }
            }
            if account.isSignedIn {
                HStack(alignment: .bottom, spacing: VESSSpacing.sm) {
                    TextField("Ask Coach", text: $draft, prompt: Text("Ask Coach").foregroundStyle(VESSColor.tertiaryText), axis: .vertical)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .lineLimit(1...5)
                        .focused($isComposerFocused)
                        .submitLabel(.send)
                        .onSubmit { ask(draft) }
                        .padding(.horizontal, VESSSpacing.md)
                        .padding(.vertical, VESSSpacing.sm)
                        .frame(minHeight: VESSHitTarget.control)
                        .accessibilityIdentifier("coach.input")
                    Button { ask(draft) } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
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
    }

    private var footer: some View {
        Group {
            if let left = remainingToday {
                Text("Coach can make mistakes. Check anything important. · ^[\(left) question](inflect: true) left today")
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
                try store.add(CoachMessage(id: UUID(), role: .assistant, text: reply.reply, createdAt: AppClock.now))
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
                    ProfileIntro(title: "An account for AI features.", text: "Only for Coach and photo estimates. Your log stays on this iPhone.")
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
