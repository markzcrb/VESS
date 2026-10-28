import SwiftUI

/// "I already use UMEVA" with nothing to restore on this iPhone (no iCloud
/// copy of the profile): the log lives only on the iPhone it was made on.
/// Restore from Apple Health, or set up again.
struct NothingToRestoreView: View {
    let canUseHealth: Bool
    let isReadingHealth: Bool
    let onHealth: () -> Void
    let onSetUpAgain: () -> Void

    var body: some View {
        BrandScreenLayout {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                Text("Nothing to restore on this iPhone.")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Your log stays on the iPhone it was made on.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                if canUseHealth {
                    Text("Apple Health can fill in your sex, birthday, height and weight, so only a few questions are left.")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .padding(.top, VESSSpacing.xs)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, VESSSpacing.huge)
        } bottom: {
            VStack(spacing: VESSSpacing.xs) {
                if canUseHealth {
                    Button(action: onHealth) {
                        Text(isReadingHealth ? "Reading Apple Health…" : "Restore from Apple Health")
                    }
                    .buttonStyle(.vessPrimary)
                    .disabled(isReadingHealth)
                    .accessibilityIdentifier("restore.health")
                    Button("Set up again", action: onSetUpAgain)
                        .buttonStyle(.brandText)
                        .accessibilityIdentifier("restore.setUpAgain")
                } else {
                    Button("Set up again", action: onSetUpAgain)
                        .buttonStyle(.vessPrimary)
                        .accessibilityIdentifier("restore.setUpAgain")
                }
            }
        }
        .background { BrandBackground() }
    }
}

/// After "Restore from Apple Health": one screen with only what Health
/// doesn't have, not the seven steps. What came from Health is shown, and
/// any basic it lacks is asked here too.
struct QuickSetupView: View {
    @Bindable var draft: OnboardingDraft
    let basics: HealthProfileBasics
    let onDone: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isComplete: Bool {
        [.goal, .basics, .activity, .diet].allSatisfy(draft.isComplete)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text("Almost there")
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    Text("A few things Apple Health doesn't know.")
                        .vessTextStyle(.editorialM)
                        .foregroundStyle(VESSColor.text)
                        .accessibilityAddTraits(.isHeader)
                    if let fromHealth {
                        fromHealth
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .accessibilityIdentifier("quickSetup.fromHealth")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                VESSTextField("What should we call you?", text: $draft.name, prompt: Text("Optional"))
                    .textContentType(.givenName)
                    .accessibilityIdentifier("quickSetup.name")

                missingBasics

                section("Goal") {
                    ForEach(WellnessGoal.allCases, id: \.self) { goal in
                        VESSChip(title: goal.title, isSelected: draft.goal == goal) { draft.goal = goal }
                    }
                }
                section("Activity") {
                    ForEach(ActivityLevel.allCases, id: \.self) { level in
                        VESSChip(title: level.title, isSelected: draft.activityLevel == level) { draft.activityLevel = level }
                    }
                }
                section("Diet") {
                    ForEach(Diet.allCases, id: \.self) { diet in
                        VESSChip(title: diet.title, isSelected: draft.diet == diet) { draft.diet = diet }
                    }
                }
                section("Allergies · any") {
                    ForEach(Allergen.allCases, id: \.self) { allergen in
                        VESSChip(title: allergen.title, isSelected: draft.allergies.contains(allergen)) {
                            draft.allergies.formSymmetricDifference([allergen])
                        }
                    }
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xl)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .vessKeyboardDoneButton()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Continue", action: onDone)
                .buttonStyle(.vessPrimary)
                .disabled(!isComplete)
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.vertical, VESSSpacing.sm)
                .background(BrandBackground())
                .accessibilityIdentifier("quickSetup.continue")
        }
        .background { BrandBackground() }
    }

    /// "From Apple Health: male · 29 · 178 cm · 68 kg".
    private var fromHealth: Text? {
        var parts: [String] = []
        if let sex = basics.sex { parts.append(String(localized: sex.title)) }
        if let age = draft.age, basics.dateOfBirth != nil { parts.append(String(localized: "\(age) years")) }
        if let height = basics.heightCentimeters { parts.append("\(VESSFormat.quantity(height))\u{00A0}cm") }
        if let weight = basics.weightKilograms { parts.append("\(VESSFormat.quantity(weight))\u{00A0}kg") }
        guard !parts.isEmpty else { return nil }
        return Text("From Apple Health: \(parts.joined(separator: " · "))")
    }

    /// Only the basics Health didn't have.
    @ViewBuilder
    private var missingBasics: some View {
        if basics.dateOfBirth == nil {
            VESSTextField("Age", text: $draft.ageText, unit: "years")
                .keyboardType(.numberPad)
                .accessibilityIdentifier("quickSetup.age")
        }
        if basics.sex == nil {
            section("Sex") {
                ForEach(Sex.allCases, id: \.self) { sex in
                    VESSChip(title: sex.title, isSelected: draft.sex == sex) { draft.sex = sex }
                }
            }
        }
        if basics.heightCentimeters == nil || basics.weightKilograms == nil {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: VESSSpacing.lg))
                : AnyLayout(HStackLayout(spacing: VESSSpacing.sm))
            layout {
                if basics.heightCentimeters == nil {
                    VESSTextField("Height", text: $draft.heightText, unit: "cm")
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("quickSetup.height")
                }
                if basics.weightKilograms == nil {
                    VESSTextField("Weight", text: $draft.weightText, unit: "kg")
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("quickSetup.weight")
                }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text(title)
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            VESSChipFlow { content() }
        }
    }
}

extension OnboardingDraft {
    /// Fills in what Apple Health has; the rest stays as it was.
    func prefill(with basics: HealthProfileBasics, now: Date, calendar: Calendar) {
        if let sex = basics.sex { self.sex = sex }
        if let birthday = basics.dateOfBirth, let years = calendar.dateComponents([.year], from: birthday, to: now).year {
            ageText = String(years)
        }
        if let height = basics.heightCentimeters { heightText = VESSFormat.quantity(height) }
        if let weight = basics.weightKilograms { weightText = VESSFormat.quantity(weight) }
    }
}
