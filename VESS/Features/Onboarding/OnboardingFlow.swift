import SwiftUI

/// Progressive onboarding: a welcome screen, then one question per screen.
/// Finishing saves the profile, and the app moves to Today.
struct OnboardingFlow: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft = OnboardingDraft()
    @State private var step: OnboardingStep = .welcome
    @State private var isMovingForward = true
    @State private var showError = false
    @State private var pendingHealthPreference: Bool?

    var body: some View {
        ZStack {
            VESSColor.background.ignoresSafeArea()

            if step == .welcome {
                WelcomeView { go(to: .goal) }
                    .transition(.opacity)
            } else {
                questionScreen
                    .transition(.opacity)
            }
        }
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

#Preview("Onboarding") {
    OnboardingFlow()
        .environment(LocalStore.preview(.empty))
}
