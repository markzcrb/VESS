import SwiftUI

/// D03: enter a workout: type, duration, effort and when. Its energy is an
/// estimate from `WorkoutEnergy` (MET × weight × hours), shown with "≈".
struct AddWorkoutView: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum When: Hashable { case now, earlier }

    @State private var type: WorkoutType = .walking
    @State private var minutes = 30
    @State private var effort: WorkoutEffort = .moderate
    @State private var when: When = .now
    @State private var startTime = AppClock.now.addingTimeInterval(-3600)
    @State private var savedCount = 0
    @State private var showError = false

    private let calendar = Calendar.current
    private static let durationStep = 5
    private static let durationRange = 5...600

    var body: some View {
        let estimate = store.profile.flatMap {
            WorkoutEnergy.estimate(type: type, effort: effort, minutes: minutes, weightKilograms: $0.weightKilograms)
        }

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                Text("Move in your own way.")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)

                section("Type") {
                    VESSChipFlow {
                        ForEach(WorkoutType.enterable, id: \.self) { option in
                            VESSChip(title: option == .other ? "Other" : option.title, isSelected: type == option) { type = option }
                        }
                    }
                }

                section("Duration") {
                    HStack {
                        VESSIconButton(systemImage: "minus", label: "Shorter") {
                            minutes = max(Self.durationRange.lowerBound, minutes - Self.durationStep)
                        }
                        .disabled(minutes <= Self.durationRange.lowerBound)
                        Spacer()
                        Text("\(minutes) min")
                            .vessTextStyle(.displayM)
                            .foregroundStyle(VESSColor.text)
                            .contentTransition(.numericText())
                        Spacer()
                        VESSIconButton(systemImage: "plus", label: "Longer") {
                            minutes = min(Self.durationRange.upperBound, minutes + Self.durationStep)
                        }
                        .disabled(minutes >= Self.durationRange.upperBound)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityValue(Text("\(minutes) min"))
                    VESSChipFlow {
                        ForEach([15, 30, 45, 60], id: \.self) { preset in
                            VESSChip(title: "\(preset) min", isSelected: minutes == preset) { minutes = preset }
                        }
                    }
                }

                section("Effort") {
                    VESSSegmented(selection: $effort, options: WorkoutEffort.allCases.map { ($0, $0.title) })
                }

                section("When") {
                    HStack(spacing: VESSSpacing.xs) {
                        VESSChip(title: "Now", isSelected: when == .now) { when = .now }
                        VESSChip(title: "Earlier today", isSelected: when == .earlier) { when = .earlier }
                    }
                    if when == .earlier {
                        DatePicker(
                            "Started at",
                            selection: $startTime,
                            in: calendar.startOfDay(for: AppClock.now)...AppClock.now,
                            displayedComponents: .hourAndMinute
                        )
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                    }
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.xl)
        }
        .vessScreenBackground(.activity)
        .vessDetailTitle("Add workout")
        .toolbar(.hidden, for: .tabBar)
        // The estimate stays in view above the button while the inputs change.
        .vessBottomAction(background: VESSColor.background) {
            VStack(alignment: .leading, spacing: VESSSpacing.md) {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.sm) {
                        Text(verbatim: estimate.map { "≈ \(VESSFormat.calories($0))" } ?? "—")
                            .vessTextStyle(.displayM)
                            .foregroundStyle(VESSColor.text)
                            .contentTransition(.numericText())
                        Text("kcal active energy")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    ActivityFootnote(text: Text("Energy is estimated from duration and effort, not measured. VESS never estimates steps."))
                }
                Button { save(estimate: estimate) } label: {
                    Text("Add \(minutes)-minute \(Text(type.sessionNoun))")
                }
                .buttonStyle(.vessPrimary)
                .accessibilityIdentifier("addWorkout.save")
            }
        }
        .sensoryFeedback(.success, trigger: savedCount)
        .vessErrorAlert(isPresented: $showError)
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: title)
            content()
        }
    }

    private func save(estimate: Double?) {
        let duration = TimeInterval(minutes * 60)
        let end = when == .now ? AppClock.now : startTime.addingTimeInterval(duration)
        let workout = Workout(
            id: UUID(), name: type.rawValue, type: type, durationMinutes: minutes, exercises: [],
            scheduledDate: nil, completedAt: end, notes: nil, templateID: nil,
            effort: effort, source: .entered, startedAt: end.addingTimeInterval(-duration),
            activeEnergyKilocalories: estimate
        )
        do {
            try store.save(workout)
            savedCount += 1
            dismiss()
        } catch {
            showError = true
        }
    }
}

private extension WorkoutType {
    /// "Add 30-minute walk".
    var sessionNoun: LocalizedStringResource {
        switch self {
        case .walking: "walk"
        case .running: "run"
        case .cycling: "ride"
        case .strength: "strength session"
        case .yoga: "yoga session"
        case .swimming: "swim"
        case .hiit: "interval session"
        case .mobility: "mobility session"
        case .other: "workout"
        }
    }
}

#Preview {
    NavigationStack {
        AddWorkoutView()
    }
    .previewEnvironment(LocalStore.preview(), health: .notConnected)
    .preferredColorScheme(.dark)
}
