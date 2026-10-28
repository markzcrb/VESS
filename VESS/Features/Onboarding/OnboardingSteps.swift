import SwiftUI

/// Shared layout for a question: the question as the Day Word-sized title,
/// one line of context, then the answers.
private struct QuestionScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xl) {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                Text(title)
                    .vessTextStyle(.dayWord)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Step 2: Goal

struct GoalStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        QuestionScaffold(title: "What brings you to VESS?", subtitle: "Choose the one that matters most right now.") {
            VESSRowGroup {
                ForEach(WellnessGoal.allCases, id: \.self) { goal in
                    VESSOptionRow(title: goal.title, isSelected: draft.goal == goal) {
                        draft.goal = goal
                    }
                }
            }
            .vessHairlineBottom()
        }
    }
}

// MARK: - Step 3: Basics

struct BasicsStep: View {
    @Bindable var draft: OnboardingDraft

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        QuestionScaffold(
            title: "A little about you",
            subtitle: "Used only to estimate your starting targets. You can change them anytime."
        ) {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                VESSTextField("What should we call you?", text: $draft.name, prompt: Text("Optional"))
                    .textContentType(.givenName)
                    .accessibilityIdentifier("onboarding.name")

                VESSTextField("Age", text: $draft.ageText, unit: "years")
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("onboarding.age")

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text("Sex")
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    VESSChipFlow {
                        ForEach(Sex.allCases, id: \.self) { sex in
                            VESSChip(title: sex.title, isSelected: draft.sex == sex) {
                                draft.sex = sex
                            }
                        }
                    }
                    Text("Used only for the energy estimate.")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                }

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: VESSSpacing.lg))
                    : AnyLayout(HStackLayout(spacing: VESSSpacing.sm))
                layout {
                    VESSTextField("Height", text: $draft.heightText, unit: "cm")
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("onboarding.height")
                    VESSTextField("Weight", text: $draft.weightText, unit: "kg")
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("onboarding.weight")
                }
            }
        }
    }
}

// MARK: - Step 4: Activity

struct ActivityStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        QuestionScaffold(title: "How active is a typical week?", subtitle: "Count everyday movement as well as exercise.") {
            VESSRowGroup {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    VESSOptionRow(title: level.title, detail: level.detail, isSelected: draft.activityLevel == level) {
                        draft.activityLevel = level
                    }
                }
            }
            .vessHairlineBottom()
        }
    }
}

// MARK: - Step 5: Diet

struct DietStep: View {
    @Bindable var draft: OnboardingDraft

    /// P01's options: one diet, and any of the "also prefer" chips.
    var body: some View {
        QuestionScaffold(title: "How do you like to eat?") {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VESSRowGroup {
                    ForEach(Diet.allCases, id: \.self) { diet in
                        VESSOptionRow(title: diet.title, isSelected: draft.diet == diet) {
                            draft.diet = diet
                        }
                    }
                }
                .vessHairlineBottom()
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Also prefer · any")
                    VESSChipFlow {
                        ForEach(FoodPreference.allCases, id: \.self) { preference in
                            VESSChip(title: preference.title, isSelected: draft.alsoPrefer.contains(preference)) {
                                draft.alsoPrefer.formSymmetricDifference([preference])
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Step 6: Allergies and restrictions

struct RestrictionsStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        QuestionScaffold(title: "Anything you avoid?", subtitle: "Select all that apply, or continue if none do.") {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                VESSChipFlow {
                    ForEach(Allergen.allCases, id: \.self) { allergen in
                        VESSChip(title: allergen.title, isSelected: draft.allergies.contains(allergen)) {
                            draft.allergies.formSymmetricDifference([allergen])
                        }
                    }
                }
                VESSTextField("Other", text: $draft.otherRestriction, prompt: Text("Anything else, optional"))
            }
        }
    }
}

// MARK: - Step 7: Focus areas

struct FocusStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        QuestionScaffold(title: "What matters to you?", subtitle: "VESS will bring these forward. Choose any.") {
            VESSChipFlow {
                ForEach(FocusArea.allCases, id: \.self) { area in
                    VESSChip(title: area.title, isSelected: draft.focusAreas.contains(area)) {
                        draft.focusAreas.formSymmetricDifference([area])
                    }
                }
            }
        }
    }
}

// MARK: - Step 8: Apple Health

/// Explains what VESS reads from Apple Health and why. No permission is
/// requested here; VESS asks when the user connects in Activity or Settings.
struct AppleHealthStep: View {
    var body: some View {
        QuestionScaffold(
            title: "Apple Health",
            subtitle: "VESS can use what Apple Health already knows, so you log less."
        ) {
            VESSRowGroup {
                // Exactly the four types HealthKitService reads.
                reason("Steps and active energy", detail: "Reflects how much you move", systemImage: "figure.walk")
                reason("Workouts", detail: "So you don't log them twice", systemImage: "dumbbell")
                reason("Weight", detail: "Shown in You, with its trend", systemImage: "scalemass")
            }
            .vessHairlineBottom()

            Text("Nothing is shared now. VESS asks once, when you connect Apple Health in Activity or Settings. It only reads, never writes, and you can change access anytime in the Health app.")
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reason(_ title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String) -> some View {
        VESSRow(
            title: Text(title),
            subtitle: Text(detail),
            leading: { VESSRowIcon(systemImage: systemImage) },
            trailing: { EmptyView() }
        )
        .accessibilityElement(children: .combine)
    }
}
