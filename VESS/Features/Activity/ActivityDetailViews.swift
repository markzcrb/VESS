import SwiftUI

// MARK: - D01 Steps

/// Steps for a day hour by hour, or the last 7 or 30 days. From Apple Health only.
struct StepsDetailView: View {
    let day: Date

    @Environment(HealthDataStore.self) private var health

    private enum Range: Hashable { case day, week, month }
    @State private var range: Range = .day

    private let calendar = Calendar.current

    var body: some View {
        let hourly = health.state.snapshot?.hourlySteps ?? []
        let target = Double(health.state.snapshot?.stepsTarget ?? UserProfile.defaultStepsTarget)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                VESSSegmented(selection: $range, options: [(.day, "Day"), (.week, "Week"), (.month, "Month")])

                switch range {
                case .day:
                    dayContent(hourly)
                case .week:
                    periodContent(hourly, days: 7, target: target, title: "The last seven days.")
                case .month:
                    periodContent(hourly, days: 30, target: target, title: "The last 30 days.")
                }

                ActivityFootnote(text: Text("From Apple Health. VESS never estimates steps."))
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(.activity)
        .vessDetailTitle("Steps")
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private func dayContent(_ hourly: [HourlyValue]) -> some View {
        let total = ActivityTrends.total(hourly, on: day, calendar: calendar)
        let isToday = calendar.isDate(day, inSameDayAs: AppClock.now)

        Text("Movement, hour by hour.")
            .vessTextStyle(.editorialL)
            .foregroundStyle(VESSColor.text)
            .accessibilityAddTraits(.isHeader)
        bigNumber(
            total.map { VESSFormat.steps($0) } ?? "—",
            caption: isToday ? Text("steps today") : Text("steps on \(day, format: .dateTime.weekday(.wide).day().month(.abbreviated))")
        )
        ActivityHourBars(values: hourly, day: day, calendar: calendar)
        if let hour = ActivityTrends.mostActiveHour(hourly, on: day, calendar: calendar) {
            VESSRowGroup {
                VESSListRow(title: Text("Most active"), value: ActivityView.hourRange(hour), showsChevron: false)
            }
            .vessHairlineBottom()
        }
    }

    @ViewBuilder
    private func periodContent(_ hourly: [HourlyValue], days: Int, target: Double, title: LocalizedStringResource) -> some View {
        let totals = ActivityTrends.dailyTotals(hourly, days: days, endingOn: day, calendar: calendar)
        let known = totals.compactMap(\.value)

        Text(title)
            .vessTextStyle(.editorialL)
            .foregroundStyle(VESSColor.text)
            .accessibilityAddTraits(.isHeader)
        bigNumber(ActivityTrends.average(totals).map { VESSFormat.steps($0) } ?? "—", caption: Text("a day"))
        ActivityDayBars(totals: totals, target: target, calendar: calendar)
        if !known.isEmpty {
            VESSRowGroup {
                VESSListRow(title: Text("Total"), value: Text(VESSFormat.steps(known.reduce(0, +))), showsChevron: false)
                VESSListRow(title: Text("Days at \(VESSFormat.steps(target)) or more"), value: Text("\(known.filter { $0 >= target }.count)"), showsChevron: false)
            }
            .vessHairlineBottom()
        }
    }

    private func bigNumber(_ value: String, caption: Text) -> some View {
        VESSMetric(value: Text(verbatim: value), context: caption, style: .displayL, contextStyle: .bodyM, spacing: VESSSpacing.sm)
            .foregroundStyle(VESSColor.text)
            .accessibilityElement(children: .combine)
    }
}

/// Daily bars for a week or a month. With a `target`, a dashed goal line and
/// the last day and days that reached it in the activity hue, the rest grey
/// (as on Activity);
/// without one, every day in the hue (D05). Labels: weekdays for 7 days,
/// else the first and last date. Decorative for VoiceOver; the screen
/// states the values.
struct ActivityDayBars: View {
    let totals: [ActivityTrends.DayTotal]
    var target: Double?
    let calendar: Calendar

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 130
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let values = totals.map { $0.value ?? 0 }
        let scaleMax = max((target ?? 0) * 1.1, values.max() ?? 0, 1)
        let barWidth: CGFloat = totals.count > 10 ? 5 : 12

        VStack(spacing: VESSSpacing.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    if let target {
                        let y = proxy.size.height * (1 - target / scaleMax)
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        }
                        .stroke(VESSColor.decorative, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(values.indices, id: \.self) { index in
                            Capsule()
                                .fill(isHighlighted(index) ? VESSColor.activity : VESSColor.chartMuted)
                                .frame(width: barWidth, height: max(4, proxy.size.height * values[index] / scaleMax) * (grown ? 1 : 0.02))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    // Drawn over the bars, so a tall bar never cuts through it.
                    if let target {
                        let y = proxy.size.height * (1 - target / scaleMax)
                        Text(verbatim: VESSFormat.steps(target))
                            .vessTextStyle(.caption)
                            .foregroundStyle(VESSColor.tertiaryText)
                            .padding(.leading, VESSSpacing.xxs)
                            .background(VESSColor.background)
                            .frame(width: proxy.size.width, alignment: .trailing)
                            .position(x: proxy.size.width / 2, y: max(y - 10, 8))
                    }
                }
            }
            .frame(height: height)
            labels
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
        }
        // Chart labels stop growing at accessibility sizes, so the target
        // label doesn't cover the bars; the numbers are in the text above.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
        .onAppear { withAnimation(reduceMotion ? nil : VESSMotion.chart) { grown = true } }
    }

    /// Days with data; with a target, only the last day and days that reached it.
    private func isHighlighted(_ index: Int) -> Bool {
        guard let value = totals[index].value else { return false }
        guard let target else { return true }
        return index == totals.count - 1 || value >= target
    }

    @ViewBuilder
    private var labels: some View {
        if totals.count <= 7 {
            HStack(spacing: 0) {
                ForEach(totals, id: \.day) { total in
                    Text(total.day, format: .dateTime.weekday(.narrow))
                        .frame(maxWidth: .infinity)
                }
            }
        } else if let first = totals.first, let last = totals.last {
            HStack {
                Text(first.day, format: .dateTime.day().month(.abbreviated))
                Spacer()
                Text(last.day, format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}

// MARK: - D02 Workout

/// One workout. Recorded workouts show Apple Health's measurements; entered
/// ones show their estimate and can be deleted.
struct WorkoutDetailView: View {
    let workoutID: UUID

    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirmation = false
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if let workout = store.workout(id: workoutID) ?? health.state.snapshot?.workouts.first(where: { $0.id == workoutID }) {
                content(workout)
            } else {
                Color.clear
            }
        }
        .vessScreenBackground(.activity)
        .vessDetailTitle("Workout")
        .toolbar(.hidden, for: .tabBar)
        .vessErrorAlert(isPresented: $showError)
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private func content(_ workout: Workout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSTag(text: workout.isRecorded ? Text("Recorded") : Text("Entered"), tone: workout.isRecorded ? .positive : .neutral)
                    Text(workout.type.title)
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .accessibilityAddTraits(.isHeader)
                    when(workout)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }

                VESSMetric(value: Text("\(workout.durationMinutes ?? 0)"), context: Text("min"), style: .displayL, contextStyle: .bodyM)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityElement(children: .combine)

                VESSRowGroup {
                    VESSListRow(
                        title: Text("Active energy"),
                        value: Text(ActivityWorkoutRow.energyValue(workout).map { "\($0) kcal" } ?? "—"),
                        showsChevron: false
                    )
                    if let meters = workout.distanceMeters, meters > 0 {
                        VESSListRow(title: Text("Distance"), value: Text("\(VESSFormat.kilometers(fromMeters: meters)) km"), showsChevron: false)
                    }
                    if let effort = workout.effort {
                        VESSListRow(title: Text("Effort"), value: Text(effort.title), showsChevron: false)
                    }
                }
                .vessHairlineBottom()

                sourceNote(workout)
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(VESSSpacing.lg)
                    .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                            .strokeBorder(VESSColor.divider, lineWidth: 1)
                    }

                if !workout.isRecorded {
                    Button("Delete") { showDeleteConfirmation = true }
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("workout.delete")
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
    }

    /// "Today · 17:10–17:55".
    private func when(_ workout: Workout) -> Text {
        guard let end = workout.completedAt else { return Text(verbatim: "") }
        let start = workout.startedAt ?? end.addingTimeInterval(-Double((workout.durationMinutes ?? 0) * 60))
        let day: Text = if calendar.isDate(end, inSameDayAs: AppClock.now) {
            Text("Today")
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: AppClock.now), calendar.isDate(end, inSameDayAs: yesterday) {
            Text("Yesterday")
        } else {
            Text(end, format: .dateTime.weekday(.wide).day().month(.abbreviated))
        }
        return Text("\(day) · \(start, format: .dateTime.hour().minute())–\(end, format: .dateTime.hour().minute())")
    }

    private func sourceNote(_ workout: Workout) -> Text {
        if workout.isRecorded {
            let device = workout.deviceName.map { Text("\($0), via Apple Health") } ?? Text("Apple Health")
            return Text("Source · \(device). Energy is a recorded measurement, not an estimate entered in VESS.")
        }
        return Text("Entered in VESS. Energy is estimated from type, duration and effort, not measured.")
    }

    private func delete() {
        do {
            try store.deleteWorkout(id: workoutID)
            dismiss()
        } catch {
            showError = true
        }
    }
}

// MARK: - D04 History

/// The last 14 days: steps per day and every workout, recorded or entered.
struct ActivityHistoryView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    private let calendar = Calendar.current

    var body: some View {
        let data = ActivityData(snapshot: health.state.snapshot, entered: store.workouts, now: AppClock.now, calendar: calendar)
        let days = (0..<14).map { data.day(offset: -$0) }
        let workouts = data.workouts(since: data.day(offset: -13))

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                Text("A record of your movement.")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)

                ForEach(days, id: \.self) { day in
                    let steps = ActivityTrends.total(data.snapshot?.hourlySteps ?? [], on: day, calendar: calendar)
                    let dayWorkouts = workouts.filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
                    if steps != nil || !dayWorkouts.isEmpty {
                        daySection(day, steps: steps, workouts: dayWorkouts, data: data)
                    }
                }

                ActivityFootnote(text: Text("Recorded workouts come from Apple Health. Entered energy is approximate; steps always come from a connected source."))
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(.activity)
        .vessDetailTitle("History")
        .toolbar(.hidden, for: .tabBar)
    }

    private func daySection(_ day: Date, steps: Double?, workouts: [Workout], data: ActivityData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let steps {
                    NavigationLink(value: ActivityRoute.steps(day: day)) {
                        header(day, data: data) {
                            HStack(spacing: 2) {
                                Text("\(VESSFormat.steps(steps)) steps")
                                    .vessTextStyle(.bodyS)
                                    .foregroundStyle(VESSColor.secondaryText)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(VESSColor.tertiaryText)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    header(day, data: data) { EmptyView() }
                }
            }

            VESSRowGroup {
                if workouts.isEmpty {
                    VESSRow(title: Text("Rest day"), subtitle: Text("Steps only")) { EmptyView() } trailing: { EmptyView() }
                } else {
                    ForEach(workouts) { workout in
                        NavigationLink(value: ActivityRoute.workout(workout.id)) {
                            ActivityWorkoutRow(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .vessHairlineBottom()
        }
    }

    private func header<Trailing: View>(_ day: Date, data: ActivityData, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Group {
                if calendar.isDate(day, inSameDayAs: data.now) {
                    Text("Today · \(day, format: .dateTime.day().month(.abbreviated))")
                } else if calendar.isDate(day, inSameDayAs: data.day(offset: -1)) {
                    Text("Yesterday · \(day, format: .dateTime.day().month(.abbreviated))")
                } else {
                    Text("\(day, format: .dateTime.weekday(.wide)) · \(day, format: .dateTime.day().month(.abbreviated))")
                }
            }
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.secondaryText)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: VESSSpacing.md)
            trailing()
        }
        .frame(minHeight: VESSHitTarget.minimum)
        .contentShape(Rectangle())
    }
}

// MARK: - D05 Statistics

/// Averages over the last 7 or 30 days, compared with the period before,
/// and the weekly pattern once there are four full weeks.
struct ActivityStatisticsView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    private enum Period: Hashable { case week, month }
    @State private var period: Period = .week

    private let calendar = Calendar.current

    var body: some View {
        let data = ActivityData(snapshot: health.state.snapshot, entered: store.workouts, now: AppClock.now, calendar: calendar)
        let days = period == .week ? 7 : 30
        let hourly = data.snapshot?.hourlySteps ?? []
        let totals = ActivityTrends.dailyTotals(hourly, days: days, endingOn: data.now, calendar: calendar)
        let comparison = ActivityTrends.periodComparison(hourly, days: days, endingOn: data.now, calendar: calendar)
        let workouts = data.workouts(since: data.day(offset: -(days - 1)))
        let pattern = ActivityTrends.weeklyPattern(hourly, before: data.now, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                HStack(spacing: VESSSpacing.xs) {
                    VESSChip(title: "Week", isSelected: period == .week) { period = .week }
                    VESSChip(title: "Month", isSelected: period == .month) { period = .month }
                }

                Text(period == .week ? "Your week in motion." : "Your month in motion.")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Steps")
                    stat(ActivityTrends.average(totals).map { VESSFormat.steps($0) } ?? "—", caption: Text("a day"))
                    ActivityDayBars(totals: totals, calendar: calendar)
                    if let comparison {
                        sentence(Self.comparisonText(comparison, period: period))
                    }
                }

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Workouts")
                    stat("\(workouts.count)", caption: Text("in \(days) days"))
                    if let text = Self.frequencyText(ActivityTrends.typesByFrequency(workouts)) {
                        sentence(text)
                    }
                }

                if let pattern {
                    VESSInsightCard(text: Self.patternText(pattern, calendar: calendar), linkTitle: nil)
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(.activity)
        .vessDetailTitle("Statistics")
        .toolbar(.hidden, for: .tabBar)
    }

    private func stat(_ value: String, caption: Text) -> some View {
        VESSMetric(value: Text(verbatim: value), context: caption, style: .displayL, contextStyle: .bodyM, spacing: VESSSpacing.sm)
            .foregroundStyle(VESSColor.text)
            .accessibilityElement(children: .combine)
    }

    private func sentence(_ text: Text) -> some View {
        text
            .vessTextStyle(.bodyM)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func comparisonText(_ comparison: ActivityTrends.Comparison, period: Period) -> Text {
        switch (comparison, period) {
        case (.aboutSame, .week): Text("About the same as the week before.")
        case (.above, .week): Text("More than the week before.")
        case (.below, .week): Text("Fewer than the week before.")
        case (.aboutSame, .month): Text("About the same as the 30 days before.")
        case (.above, .month): Text("More than the 30 days before.")
        case (.below, .month): Text("Fewer than the 30 days before.")
        }
    }

    /// "Most often: walking, then strength." Only with a clear first.
    private static func frequencyText(_ types: [(type: WorkoutType, count: Int)]) -> Text? {
        guard let first = types.first, first.count > (types.dropFirst().first?.count ?? 0) else { return nil }
        if let second = types.dropFirst().first {
            return Text("Most often: \(Text(first.type.activityNoun)), then \(Text(second.type.activityNoun)).")
        }
        return Text("Most often: \(Text(first.type.activityNoun)).")
    }

    private static func patternText(_ pattern: ActivityTrends.WeeklyPattern, calendar: Calendar) -> Text {
        let quietest = calendar.standaloneWeekdaySymbols[(pattern.quietestWeekday - 1) % 7]
        let lead: Text = switch pattern.weekendsBusiest {
        case true: Text("You move most on weekends.")
        case false: Text("You move most on weekdays.")
        case nil: Text("Weekends and weekdays are about the same.")
        }
        return Text("\(lead) Your quietest day is usually \(quietest).")
    }
}
