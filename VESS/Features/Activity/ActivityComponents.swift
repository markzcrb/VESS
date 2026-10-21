import SwiftUI

/// What the Activity screens show: Apple Health's snapshot (if any) and the
/// workouts the user entered. Derived values only; no rules of its own.
struct ActivityData {
    let snapshot: HealthSnapshot?
    let entered: [Workout]
    let now: Date
    let calendar: Calendar

    var today: Date { calendar.startOfDay(for: now) }

    /// Values are known up to the last sync, so "so far" comparisons stop there.
    var dataTime: Date { snapshot?.updatedAt ?? now }

    /// Recorded and entered workouts that finished on or after `start`, newest first.
    func workouts(since start: Date) -> [Workout] {
        ((snapshot?.workouts ?? []) + entered)
            .filter { ($0.completedAt ?? .distantPast) >= start }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func day(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    /// Daily step totals, oldest first, ending today.
    func dailySteps(days: Int) -> [ActivityTrends.DayTotal] {
        ActivityTrends.dailyTotals(snapshot?.hourlySteps ?? [], days: days, endingOn: now, calendar: calendar)
    }

    /// "Tue", "Today" or "Yesterday" for row labels.
    func shortDay(_ date: Date) -> Text {
        if calendar.isDate(date, inSameDayAs: now) { return Text("Today") }
        return Text(date, format: .dateTime.weekday(.abbreviated))
    }
}

/// Activity and the screens reached from it, pushed by value so they stack
/// in order on Today's navigation stack.
enum ActivityRoute: Hashable {
    case activity
    case steps(day: Date)
    case workout(UUID)
    case addWorkout
    case history
    case statistics
}

// MARK: - Workout row

/// "Sun · Run · 5.2 km [RECORDED] · 32 min · Apple Watch · 368 kcal". Entered
/// workouts show "≈" and their effort; the tag carries the meaning.
struct ActivityWorkoutRow: View {
    let workout: Workout
    /// The short day on the left; `nil` in lists already grouped by day.
    var day: Text?
    var showsChevron = true

    var body: some View {
        HStack(alignment: .center, spacing: VESSSpacing.md) {
            if let day {
                day
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: VESSSpacing.huge, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VESSSpacing.xs) { title; tag }
                    VStack(alignment: .leading, spacing: VESSSpacing.xxs) { title; tag }
                }
                subtitle
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: VESSSpacing.xs)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: Self.energyValue(workout) ?? "—")
                    .vessTextStyle(.numberRow)
                    .foregroundStyle(VESSColor.text)
                Text("kcal")
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VESSColor.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, VESSSpacing.sm + 2)
        .frame(minHeight: VESSSize.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Group {
            if let meters = workout.distanceMeters, meters > 0 {
                Text("\(Text(workout.type.title)) · \(VESSFormat.kilometers(fromMeters: meters)) km")
            } else {
                Text(workout.type.title)
            }
        }
        .vessTextStyle(.bodyMStrong)
        .foregroundStyle(VESSColor.text)
    }

    private var tag: some View {
        VESSTag(text: workout.isRecorded ? Text("Recorded") : Text("Entered"), tone: workout.isRecorded ? .positive : .neutral)
    }

    private var subtitle: Text {
        let minutes = Text("\(workout.durationMinutes ?? 0) min")
        if workout.isRecorded {
            if let device = workout.deviceName { return Text("\(minutes) · \(device)") }
            return Text("\(minutes) · Apple Health")
        }
        if let effort = workout.effort { return Text("\(minutes) · \(Text(effort.phrase))") }
        return minutes
    }

    /// "368" recorded, "≈ 551" entered.
    static func energyValue(_ workout: Workout) -> String? {
        guard let kcal = workout.activeEnergyKilocalories else { return nil }
        let value = VESSFormat.calories(kcal)
        return workout.isRecorded ? value : "≈ \(value)"
    }
}

// MARK: - Hour bars

/// Steps hour by hour: 24 slots on a dashed baseline, labelled 00 06 12 18
/// 24. Decorative for VoiceOver; callers state the total and busiest hour.
struct ActivityHourBars: View {
    let values: [HourlyValue]
    let day: Date
    let calendar: Calendar
    var tint: Color = VESSColor.activity

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 140
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let hours = hourly
        let scaleMax = max(hours.max() ?? 0, 1)

        VStack(spacing: VESSSpacing.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height - 1))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height - 1))
                    }
                    .stroke(VESSColor.decorative, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(hours.indices, id: \.self) { index in
                            Capsule()
                                .fill(tint)
                                .frame(width: 6, height: hours[index] > 0 ? max(6, proxy.size.height * hours[index] / scaleMax) * (grown ? 1 : 0.02) : 0)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(height: height)
            HStack {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { label in
                    Text(verbatim: label)
                    if label != "24" { Spacer() }
                }
            }
            .vessTextStyle(.caption)
            .foregroundStyle(VESSColor.tertiaryText)
        }
        .accessibilityHidden(true)
        .onAppear { withAnimation(reduceMotion ? nil : VESSMotion.chart) { grown = true } }
    }

    /// 24 values, one per hour of `day`; missing hours are 0.
    private var hourly: [Double] {
        let start = calendar.startOfDay(for: day)
        var result = Array(repeating: 0.0, count: 24)
        for value in values {
            let hour = Int(value.start.timeIntervalSince(start) / 3600)
            if (0..<24).contains(hour) { result[hour] += value.value }
        }
        return result
    }
}

// MARK: - Footnote and links

/// The quiet line under Activity lists.
struct ActivityFootnote: View {
    let text: Text

    var body: some View {
        text
            .vessTextStyle(.caption)
            .foregroundStyle(VESSColor.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section header whose trailing link pushes a screen.
struct ActivitySectionHeader: View {
    let title: LocalizedStringResource
    let linkTitle: LocalizedStringResource
    let route: ActivityRoute

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: VESSSpacing.md)
            NavigationLink(value: route) {
                HStack(spacing: 2) {
                    Text(linkTitle)
                        .vessTextStyle(.bodyS)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VESSColor.tertiaryText)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(VESSColor.secondaryText)
                .frame(minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

extension View {
    /// The pushes Activity screens share.
    func activityDestinations() -> some View {
        navigationDestination(for: ActivityRoute.self) { route in
            switch route {
            case .activity: ActivityView()
            case .steps(let day): StepsDetailView(day: day)
            case .workout(let id): WorkoutDetailView(workoutID: id)
            case .addWorkout: AddWorkoutView()
            case .history: ActivityHistoryView()
            case .statistics: ActivityStatisticsView()
            }
        }
    }
}
