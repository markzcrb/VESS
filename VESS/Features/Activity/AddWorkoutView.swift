import SwiftUI

/// D03: enter a workout: type, duration, effort and when. Its energy is an
/// estimate from `WorkoutEnergy` (MET × weight × hours), shown with "≈".
///
/// Only a one-line estimate and the button are pinned, so the inputs above
/// always scroll clear of them (iPhone SE and AX5 included).
struct AddWorkoutView: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Inside the Add sheet (21), which has its own title and X.
    var embedded = false

    private enum When: Hashable { case now, earlier }

    @State private var type: WorkoutType = .walking
    @State private var minutes = 30
    @State private var showCustomDuration = false
    @State private var effort: WorkoutEffort = .moderate
    @State private var when: When = .now
    @State private var startTime = AppClock.now.addingTimeInterval(-3600)
    @State private var showTimePicker = false
    @State private var showError = false

    private let calendar = Calendar.current
    private static let presets = [15, 30, 45, 60]
    private static let durationStep = 5
    private static let durationRange = 5...600

    var body: some View {
        let estimate = store.profile.flatMap {
            WorkoutEnergy.estimate(type: type, effort: effort, minutes: minutes, weightKilograms: $0.weightKilograms)
        }

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                // The editorial line belongs to the standalone screen.
                if !embedded {
                    Text("Move in your own way.")
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .accessibilityAddTraits(.isHeader)
                }

                section("Type") { typeCards }
                section("Duration") { duration }
                section("Effort") {
                    VESSSegmented(selection: $effort, options: WorkoutEffort.allCases.map { ($0, $0.title) })
                }
                section("When") { whenControl }

                // At accessibility sizes the estimate sits here, so the pinned
                // area is only the button and the form keeps room to scroll.
                if dynamicTypeSize.isAccessibilitySize {
                    estimateLine(estimate)
                }
                ActivityFootnote(text: Text("Energy is estimated from duration and effort, not measured. VESS never estimates steps."))
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.xl)
        }
        .vessScreenBackground(.activity)
        .vessStandaloneTitle("Add workout", embedded: embedded)
        .vessBottomAction(background: VESSColor.background) {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                if !dynamicTypeSize.isAccessibilitySize {
                    estimateLine(estimate)
                }
                Button { save(estimate: estimate) } label: {
                    // A non-breaking hyphen keeps "30-minute" together.
                    Text("Add \(minutes)\u{2011}minute \(Text(type.sessionNoun))")
                }
                .buttonStyle(.vessPrimary)
                .accessibilityIdentifier("addWorkout.save")
            }
        }
        .vessErrorAlert(isPresented: $showError)
    }

    // MARK: Sections

    /// "≈ 137 kcal active energy · estimate".
    private func estimateLine(_ estimate: Double?) -> some View {
        VESSMetric(
            value: Text(verbatim: estimate.map { "≈ \(VESSFormat.calories($0))" } ?? "—"),
            context: Text("kcal active energy · estimate"),
            style: .numberRow,
            contextStyle: .bodyS
        )
        // Wraps rather than truncates: "estimate" must always show.
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(VESSColor.text)
        .contentTransition(.numericText())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("addWorkout.estimate")
    }

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: title)
            content()
        }
    }

    private var typeCards: some View {
        LazyVGrid(columns: VESSPickTile.columns(for: dynamicTypeSize), spacing: VESSSpacing.xs) {
            ForEach(WorkoutType.enterable, id: \.self) { option in
                VESSPickTile(
                    title: Text(option == .other ? "Other" : option.title),
                    systemImage: option.symbol,
                    isSelected: type == option
                ) { type = option }
                .accessibilityIdentifier("addWorkout.type.\(option.rawValue)")
            }
        }
    }

    /// 15 · 30 · 45 · 60 min, and a small Custom chip with a stepper for
    /// any other length.
    private var duration: some View {
        let isCustom = showCustomDuration || !Self.presets.contains(minutes)
        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSChipFlow {
                ForEach(Self.presets, id: \.self) { preset in
                    VESSChip(title: "\(preset) min", isSelected: !isCustom && minutes == preset) {
                        minutes = preset
                        withAnimation(reduceMotion ? nil : VESSMotion.selection) { showCustomDuration = false }
                    }
                }
                // Shows the length only when it isn't one of the presets.
                VESSChip(title: Self.presets.contains(minutes) ? "Custom" : "\(minutes) min", isSelected: isCustom) {
                    withAnimation(reduceMotion ? nil : VESSMotion.selection) { showCustomDuration = true }
                }
                .accessibilityLabel(isCustom ? Text("Custom, \(minutes) min") : Text("Custom"))
                .accessibilityIdentifier("addWorkout.customDuration")
            }
            if isCustom {
                HStack(spacing: VESSSpacing.md) {
                    VESSIconButton(systemImage: "minus", label: "Shorter") {
                        minutes = max(Self.durationRange.lowerBound, minutes - Self.durationStep)
                    }
                    .disabled(minutes <= Self.durationRange.lowerBound)
                    Text("\(minutes) min")
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                    VESSIconButton(systemImage: "plus", label: "Longer") {
                        minutes = min(Self.durationRange.upperBound, minutes + Self.durationStep)
                    }
                    .disabled(minutes >= Self.durationRange.upperBound)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Duration")
                .accessibilityValue(Text("\(minutes) min"))
            }
        }
    }

    /// Now, or earlier today with the start time on a wheel.
    private var whenControl: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            HStack(spacing: VESSSpacing.xs) {
                VESSChip(title: "Now", isSelected: when == .now) {
                    withAnimation(reduceMotion ? nil : VESSMotion.selection) { when = .now }
                }
                VESSChip(title: "Earlier today", isSelected: when == .earlier) {
                    withAnimation(reduceMotion ? nil : VESSMotion.selection) {
                        when = .earlier
                        showTimePicker = true
                    }
                }
                .accessibilityIdentifier("addWorkout.earlier")
            }
            if when == .earlier {
                DrinkTimeRow(
                    time: $startTime,
                    isExpanded: $showTimePicker,
                    range: calendar.startOfDay(for: AppClock.now)...AppClock.now,
                    identifier: "addWorkout.time"
                )
            }
        }
    }

    // MARK: Actions

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
            undo.show(Text("Added \(minutes)-minute \(Text(type.sessionNoun))")) { store in
                try store.deleteWorkout(id: workout.id)
            }
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

#if DEBUG
#Preview("Dark") {
    NavigationStack {
        AddWorkoutView()
    }
    .previewEnvironment(LocalStore.preview(), health: .notConnected)
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    NavigationStack {
        AddWorkoutView()
    }
    .previewEnvironment(LocalStore.preview(), health: .notConnected)
    .preferredColorScheme(.light)
}
#endif
