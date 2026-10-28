import SwiftUI

/// Progressive onboarding: B02, then one question per screen. "I already
/// use UMEVA" signs in first, then restores instead of asking again: the
/// profile from the user's iCloud ("Welcome back"), or, with nothing to
/// restore, the basics from Apple Health and one short screen for the rest.
/// The log itself is only ever on the iPhone it was made on. Finishing
/// saves the profile; `onFinish(restored)` runs first, so the app shows B03
/// (or B03 as "Welcome back").
struct OnboardingFlow: View {
    var onFinish: (_ restored: Bool) -> Void = { _ in }
    @Environment(LocalStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(ProfileMirror.self) private var mirror
    @Environment(HealthDataStore.self) private var health
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft = OnboardingDraft()
    @State private var step: OnboardingStep = .welcome
    @State private var isMovingForward = true
    @State private var showError = false
    @State private var pendingHealthPreference: Bool?
    @State private var showSignIn = false

    /// After "I already use UMEVA" and sign-in.
    private enum Restore: Equatable {
        case checking
        case nothing
        case quickSetup(HealthProfileBasics)
    }
    @State private var restore: Restore?
    @State private var isReadingHealth = false

    var body: some View {
        ZStack {
            // The brand screens' plain pearl / graphite, through every question.
            BrandBackground()

            if let restore {
                restoreScreen(restore)
                    .transition(.opacity)
            } else if step == .welcome {
                WelcomeView(onStart: { go(to: .goal) }, onSignIn: signIn)
                    .transition(.opacity)
            } else {
                questionScreen
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSignIn) {
            if account.isSignedIn { afterSignIn() }
        } content: {
            AISignInSheet(title: "Welcome back.",
                          text: "Signing in brings back Coach, photo estimates and AI Chef, and UMEVA+ comes back with your Apple Account. Your log is never stored in your account.")
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: restore)
        .vessErrorAlert(isPresented: $showError) {
            if let pendingHealthPreference { finish(prefersAppleHealth: pendingHealthPreference) }
        }
    }

    // MARK: Question screens

    private var questionScreen: some View {
        VStack(spacing: 0) {
            progressHeader

            // The whole scroll view is replaced per step, inside a ZStack so the
            // outgoing and incoming steps overlay each other during the
            // transition. (In the VStack they were laid out together, which
            // left a ghost of the previous step and blocked taps.)
            ZStack {
                ScrollView {
                    stepContent
                        .padding(.horizontal, VESSSpacing.screenInset)
                        .padding(.top, VESSSpacing.xl)
                        .padding(.bottom, VESSSpacing.xl)
                }
                .scrollDismissesKeyboard(.interactively)
                .id(step)
                .transition(stepTransition)
            }
            .frame(maxHeight: .infinity)
            .clipped()
            .vessKeyboardDoneButton()

            // Docked above the keyboard. (Hiding it while the keyboard is up
            // moved the layout under taps when focus changed between fields.)
            footer
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.sm)
                .padding(.bottom, VESSSpacing.md)
        }
    }

    private var progressHeader: some View {
        let questions = OnboardingStep.questions
        let index = (questions.firstIndex(of: step) ?? 0) + 1

        // Back · centred tracked-caps title · step counter at the 20 pt
        // margin, then a neutral progress line (progress isn't a link).
        return VStack(spacing: VESSSpacing.sm) {
            // The title is centred on the screen, not between the controls.
            Text(step.headerTitle)
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.text)
                .accessibilityAddTraits(.isHeader)
                .multilineTextAlignment(.center)
                // Clear of the back button and the counter on either side.
                .padding(.horizontal, VESSSpacing.screenInset + VESSHitTarget.minimum)
                .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum)
                .overlay {
                HStack {
                    Button {
                        if let previous = step.previous { go(to: previous) }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                            .foregroundStyle(VESSColor.text)
                            .frame(width: VESSHitTarget.minimum, height: VESSHitTarget.minimum)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                    .accessibilityShowsLargeContentViewer {
                        Label("Back", systemImage: "chevron.left")
                    }
                    Spacer()
                    Text(verbatim: "\(index)/\(questions.count)")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.secondaryText)
                        .monospacedDigit()
                        .accessibilityLabel(Text("Step \(index) of \(questions.count)"))
                }
                .padding(.leading, VESSSpacing.screenInset - (VESSHitTarget.minimum - 17) / 2)
                .padding(.trailing, VESSSpacing.screenInset)
                }

            VESSVesselLine(value: Double(index) / Double(questions.count), tint: VESSColor.text)
                .padding(.horizontal, VESSSpacing.screenInset)
        }
        .padding(.top, VESSSpacing.xs)
        // Like a navigation bar, the header stops growing at large sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: EmptyView()
        case .goal: GoalStep(draft: draft)
        case .basics: BasicsStep(draft: draft)
        case .activity: ActivityStep(draft: draft)
        case .diet: DietStep(draft: draft)
        case .restrictions: RestrictionsStep(draft: draft)
        case .focus: FocusStep(draft: draft)
        case .appleHealth: AppleHealthStep()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if step == .appleHealth {
            VStack(spacing: VESSSpacing.sm) {
                Button("Use Apple Health") { finish(prefersAppleHealth: true) }
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("onboarding.useAppleHealth")
                Button("Not now") { finish(prefersAppleHealth: false) }
                    .buttonStyle(.vessSecondary)
                    .accessibilityIdentifier("onboarding.notNow")
            }
        } else {
            Button("Continue") {
                if let next = step.next { go(to: next) }
            }
            .buttonStyle(.vessPrimary)
            .disabled(!draft.isComplete(step))
            .accessibilityIdentifier("onboarding.continue")
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let edge: Edge = isMovingForward ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .opacity
        )
    }

    // MARK: Actions

    private func go(to newStep: OnboardingStep) {
        isMovingForward = newStep > step
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
            step = newStep
        }
    }

    private func signIn() {
        if account.isSignedIn {
            afterSignIn()
        } else {
            showSignIn = true
        }
    }

    // MARK: Restore

    @ViewBuilder
    private func restoreScreen(_ stage: Restore) -> some View {
        switch stage {
        case .checking:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Looking for your profile"))
        case .nothing:
            NothingToRestoreView(canUseHealth: health.canConnect, isReadingHealth: isReadingHealth,
                                 onHealth: restoreFromHealth, onSetUpAgain: setUpAgain)
        case .quickSetup(let basics):
            QuickSetupView(draft: draft, basics: basics) { finish(prefersAppleHealth: true) }
        }
    }

    /// Signed in: the profile from iCloud if there is one, then "Welcome
    /// back"; otherwise the "Nothing to restore" screen. Never the questions.
    private func afterSignIn() {
        restore = .checking
        Task {
            if let mirrored = await mirror.load() {
                do {
                    onFinish(true)
                    try store.saveProfile(mirrored.makeProfile(now: .now, calendar: .current))
                } catch {
                    restore = .nothing
                    showError = true
                }
            } else {
                restore = .nothing
            }
        }
    }

    private func restoreFromHealth() {
        isReadingHealth = true
        Task {
            let basics = await health.readBasics() ?? HealthProfileBasics()
            draft.prefill(with: basics, now: .now, calendar: .current)
            isReadingHealth = false
            restore = .quickSetup(basics)
        }
    }

    private func setUpAgain() {
        restore = nil
        go(to: .goal)
    }

    private func finish(prefersAppleHealth: Bool) {
        pendingHealthPreference = prefersAppleHealth
        guard let profile = draft.makeProfile(prefersAppleHealth: prefersAppleHealth, now: .now, calendar: .current) else {
            // A required answer is missing; return to the first incomplete step.
            if let incomplete = OnboardingStep.questions.first(where: { !draft.isComplete($0) }) {
                go(to: incomplete)
            }
            return
        }
        do {
            onFinish(false)
            try store.saveProfile(profile)
        } catch {
            showError = true
        }
    }
}

private extension OnboardingStep {
    /// The centred caps title above each question.
    var headerTitle: LocalizedStringResource {
        switch self {
        case .welcome: "Welcome"
        case .goal: "Goal"
        case .basics: "About you"
        case .activity: "Activity"
        case .diet: "Diet"
        case .restrictions: "Avoid"
        case .focus: "Focus"
        case .appleHealth: "Apple Health"
        }
    }
}

#if DEBUG
#Preview("Onboarding") {
    OnboardingFlow()
        .environment(LocalStore.preview(.empty))
        .environment(AccountStore.make())
        .environment(ProfileMirror(storage: nil))
        .environment(HealthDataStore())
}
#endif
