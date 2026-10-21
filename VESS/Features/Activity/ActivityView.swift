import SwiftUI

/// Activity (09), pushed from Today's Steps. Steps, active energy and
/// recorded workouts come from Apple Health, read-only; entered workouts
/// are stored in VESS. Without Health it shows "—" (S4): steps are never
/// estimated. Also the syncing (D06) and sync error (D07) states.
struct ActivityView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    @State private var showInfo = false
    @State private var showSteps = false

    private let calendar = Calendar.current

    var body: some View {
        let data = ActivityData(snapshot: health.state.snapshot, entered: store.workouts, now: AppClock.now, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                switch health.state {
                case .notConnected, .nothingShared:
                    disconnected(data)
                case .syncing:
                    syncing(data)
                case .available(let snapshot):
                    connected(snapshot, data: data)
                case .failed(let lastKnown):
                    failed(lastKnown, data: data)
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(.activity)
        .vessDetailTitle("Activity")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About Activity")
            }
        }
        .sheet(isPresented: $showInfo) { ActivityInfoSheet() }
        .navigationDestination(isPresented: $showSteps) { StepsDetailView(day: data.now) }
    }

    private var stepsTarget: Int {
        store.profile?.dailyStepsTarget ?? UserProfile.defaultStepsTarget
    }

    // MARK: Connected (09)

    @ViewBuilder
    private func connected(_ snapshot: HealthSnapshot, data: ActivityData) -> some View {
        let weekday = Text(data.now, format: .dateTime.weekday(.wide))
        let typicalSteps = ActivityTrends.typical(snapshot.hourlySteps, at: data.dataTime, calendar: calendar)
        let typicalEnergy = ActivityTrends.typical(snapshot.hourlyActiveEnergy, at: data.dataTime, calendar: calendar)
        let stepsTrend = typicalSteps.map { Self.trend(ActivityTrends.compare(Double(snapshot.steps), with: $0)) }
        let energyTrend: VESSTrend? = if let energy = snapshot.activeEnergyKilocalories, let typicalEnergy {
            Self.trend(ActivityTrends.compare(energy, with: typicalEnergy))
        } else {
            nil
        }
        let todayWorkouts = data.workouts(since: data.today)

        VESSScoreRing(
            value: VESSFormat.steps(Double(snapshot.steps)),
            label: "Steps",
            sublabel: Text("of \(VESSFormat.steps(Double(snapshot.stepsTarget))) · Apple Health"),
            progress: snapshot.stepsFraction,
            metric: .activity
        )
        .frame(maxWidth: .infinity)

        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSRowGroup {
                VESSMetricRow(systemImage: "figure.walk", label: "Steps", value: VESSFormat.steps(Double(snapshot.steps)), trend: stepsTrend)
                VESSMetricRow(
                    systemImage: "bolt",
                    label: "Active energy",
                    value: snapshot.activeEnergyKilocalories.map { "\(VESSFormat.calories($0)) kcal" } ?? "—",
                    trend: energyTrend
                )
                VESSMetricRow(systemImage: "dumbbell", label: "Workouts", value: "\(todayWorkouts.count)")
            }
            .vessHairlineBottom()
            if stepsTrend != nil || energyTrend != nil {
                VESSLegendChip(text: Text("Today vs. a typical \(weekday)"))
            }
        }

        if let typicalSteps {
            VESSInsightCard(
                text: Text("\(VESSFormat.steps(Double(snapshot.steps))) steps so far. By this time on a typical \(weekday), you're at about \(VESSFormat.steps((typicalSteps / 10).rounded() * 10)). Last synced \(snapshot.updatedAt, format: .dateTime.hour().minute())."),
                linkTitle: "See step history",
                action: { showSteps = true }
            )
        }

        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            ActivitySectionHeader(title: "Steps · last 7 days", linkTitle: "Statistics", route: .statistics)
            let days = data.dailySteps(days: 7)
            VESSWeekBars(
                bars: days.map { VESSWeekBars.Bar(day: $0.day, value: $0.value ?? 0) },
                target: Double(snapshot.stepsTarget),
                targetLabel: VESSFormat.steps(Double(snapshot.stepsTarget)),
                tint: VESSColor.activity,
                highlightsReached: true
            )
            .accessibilityHidden(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Steps, last 7 days"))
            // "Wednesday 7,840, Thursday 5,210, …"
            .accessibilityValue(Text(days.map { "\($0.day.formatted(.dateTime.weekday(.wide))) \(VESSFormat.steps($0.value ?? 0))" }.joined(separator: ", ")))
        }

        workoutsSection(workouts: data.workouts(since: data.day(offset: -6)), data: data)

        ActivityFootnote(text: Text("Energy for entered workouts is an estimate from duration and effort, not a measurement. VESS never estimates steps."))
        logWorkoutButton
    }

    private static func trend(_ comparison: ActivityTrends.Comparison) -> VESSTrend {
        switch comparison {
        case .above: .up
        case .below: .down
        case .aboutSame: .flat
        }
    }

    // MARK: Not connected (S4)

    @ViewBuilder
    private func disconnected(_ data: ActivityData) -> some View {
        VStack(spacing: VESSSpacing.xl) {
            VESSScoreRing(value: "—", label: "Steps", sublabel: Text("No source connected"), progress: 0, metric: .activity)
            Text("VESS doesn't guess your steps.")
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            disconnectedMessage
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if health.state == .notConnected, health.canConnect {
                Button("Connect Apple Health") {
                    Task { await health.connect(stepsTarget: stepsTarget) }
                }
                .buttonStyle(.vessPrimary)
                .accessibilityIdentifier("activity.connect")
            }
        }
        .frame(maxWidth: .infinity)

        enteredSection(title: "Entered by you", data: data)
        logWorkoutButton
    }

    private var disconnectedMessage: Text {
        if health.state == .nothingShared {
            return Text("Apple Health hasn't shared steps or workouts with VESS. You can allow access in the Health app, under your profile › Apps › VESS. Until then, only workouts you enter appear.")
        }
        if !health.canConnect {
            return Text("Apple Health isn't available on this device, so only workouts you enter appear.")
        }
        return Text("Connect Apple Health to see steps and recorded workouts here and on Today. Until then, only workouts you enter appear.")
    }

    // MARK: Syncing (D06)

    @ViewBuilder
    private func syncing(_ data: ActivityData) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            Text("Syncing your movement.")
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("Getting today's steps and recorded workouts from Apple Health.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            Text("Syncing with Apple Health…")
                .vessTextStyle(.titleL)
                .foregroundStyle(VESSColor.text)
            VStack(spacing: VESSSpacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: VESSRadius.small, style: .continuous)
                        .fill(VESSColor.fill)
                        .frame(height: 32)
                }
            }
            .vessShimmer()
            .accessibilityHidden(true)
        }

        enteredSection(title: "Entered by you", data: data)
        ActivityFootnote(text: Text("Your entered workouts are saved while Health data refreshes."))
        logWorkoutButton
    }

    // MARK: Sync error (D07)

    @ViewBuilder
    private func failed(_ lastKnown: HealthSnapshot?, data: ActivityData) -> some View {
        VStack(spacing: VESSSpacing.sm) {
            Group {
                if let lastKnown {
                    Text("Couldn't reach Apple Health. Showing known data from \(lastKnown.updatedAt, format: .dateTime.hour().minute()).")
                } else {
                    Text("Couldn't reach Apple Health. Your entered workouts are still here.")
                }
            }
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VESSSpacing.md)
            .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                    .strokeBorder(VESSColor.divider, lineWidth: 1)
            }
            Button("Retry") {
                Task { await health.refresh(stepsTarget: stepsTarget) }
            }
            .buttonStyle(.vessSecondary)
            .accessibilityIdentifier("activity.retry")
        }

        if let lastKnown {
            VESSScoreRing(
                value: VESSFormat.steps(Double(lastKnown.steps)),
                label: "Steps",
                sublabel: Text("of \(VESSFormat.steps(Double(lastKnown.stepsTarget))) · last updated \(lastKnown.updatedAt, format: .dateTime.hour().minute())"),
                progress: lastKnown.stepsFraction,
                metric: .activity
            )
            .frame(maxWidth: .infinity)

            Text("Your movement is still here.")
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VESSRowGroup {
                VESSListRow(title: Text("Steps"), value: Text(VESSFormat.steps(Double(lastKnown.steps))), showsChevron: false)
                VESSListRow(
                    title: Text("Active energy"),
                    value: Text(lastKnown.activeEnergyKilocalories.map { "\(VESSFormat.calories($0)) kcal" } ?? "—"),
                    showsChevron: false
                )
                VESSListRow(title: Text("Workouts"), value: Text("\(data.workouts(since: data.today).count)"), showsChevron: false)
            }
            .vessHairlineBottom()

            VStack(alignment: .leading, spacing: VESSSpacing.md) {
                VESSSectionHeader(title: "Movement")
                ActivityHourBars(values: lastKnown.hourlySteps, day: data.now, calendar: calendar)
                Group {
                    if let hour = ActivityTrends.mostActiveHour(lastKnown.hourlySteps, on: data.now, calendar: calendar) {
                        Text("Most active \(Self.hourRange(hour)). Known values are kept until the next successful sync.")
                    } else {
                        Text("Known values are kept until the next successful sync.")
                    }
                }
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        enteredSection(title: "Entered workouts are saved", data: data)
        logWorkoutButton
    }

    // MARK: Shared

    @ViewBuilder
    private func enteredSection(title: LocalizedStringResource, data: ActivityData) -> some View {
        let entered = data.entered.filter { ($0.completedAt ?? .distantPast) >= data.day(offset: -6) }
        if !entered.isEmpty {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                VESSSectionHeader(title: title)
                workoutRows(entered, data: data)
            }
        }
    }

    private func workoutsSection(workouts: [Workout], data: ActivityData) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            ActivitySectionHeader(title: "Workouts", linkTitle: "History", route: .history)
            if workouts.isEmpty {
                Text("No workouts in the last 7 days.")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .padding(.vertical, VESSSpacing.sm)
            } else {
                workoutRows(workouts, data: data)
            }
        }
    }

    private func workoutRows(_ workouts: [Workout], data: ActivityData) -> some View {
        VESSRowGroup {
            ForEach(workouts) { workout in
                NavigationLink(value: ActivityRoute.workout(workout.id)) {
                    ActivityWorkoutRow(workout: workout, day: workout.completedAt.map { data.shortDay($0) })
                }
                .buttonStyle(.plain)
            }
        }
        .vessHairlineBottom()
    }

    private var logWorkoutButton: some View {
        NavigationLink(value: ActivityRoute.addWorkout) {
            Label("Log a workout", systemImage: "plus")
        }
        .buttonStyle(.vessSecondary)
        .accessibilityIdentifier("activity.logWorkout")
    }

    /// "12:00–13:00", in the user's clock format.
    static func hourRange(_ start: Date) -> Text {
        let end = start.addingTimeInterval(3600)
        return Text("\(start, format: .dateTime.hour().minute())–\(end, format: .dateTime.hour().minute())")
    }
}

/// Where Activity's numbers come from. Opened from the info button.
private struct ActivityInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                    Text("Where these numbers come from")
                        .vessTextStyle(.editorialM)
                        .foregroundStyle(VESSColor.text)
                    note("Steps, active energy and recorded workouts come from Apple Health. VESS only reads them; it never writes to Health.")
                    note("Workouts you enter are kept in VESS. Their energy is an estimate from type, duration and effort, so it's shown with ≈.")
                    note("Arrows compare today with the median of your last four same weekdays, up to the same time. Within 10 % counts as about usual.")
                    note("VESS never estimates steps. Without Apple Health, steps show —.")
                }
                .padding(VESSSpacing.screenInset)
            }
            .background(VESSColor.card)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(VESSRadius.sheet)
    }

    private func note(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .vessTextStyle(.bodyM)
            .foregroundStyle(VESSColor.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Connected") {
    NavigationStack {
        ActivityView()
    }
    .previewEnvironment(LocalStore.preview(), health: .available(MockData.preview.health))
    .preferredColorScheme(.dark)
}

#Preview("Syncing") {
    NavigationStack {
        ActivityView()
    }
    .previewEnvironment(LocalStore.preview(), health: .syncing)
    .preferredColorScheme(.dark)
}

#Preview("Not connected") {
    NavigationStack {
        ActivityView()
    }
    .previewEnvironment(LocalStore.preview(), health: .notConnected)
    .preferredColorScheme(.dark)
}
