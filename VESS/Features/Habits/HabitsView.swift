import SwiftUI

/// 14: habits. This week as small rings, today's share as a neutral ring,
/// one editorial line, today's list with each habit's week, the last four
/// weeks in greyscale, and Add a habit. No streaks, scores or penalties.
struct HabitsView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @Environment(ReminderService.self) private var reminders

    @State private var editing: HabitSheetRequest?
    @State private var showEdit = false
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let habits = store.habits
        let log = HabitLogLoader.log(
            store: store,
            health: health.state.snapshot,
            from: calendar.date(byAdding: .day, value: -35, to: now) ?? now,
            through: now,
            calendar: calendar
        )
        let today = HabitRules.status(habits, on: now, today: now, log: log, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                if habits.isEmpty {
                    emptyState
                } else {
                    HabitWeekStrip(habits: habits, today: now, log: log, calendar: calendar)
                    VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                        ring(today, now: now)
                        editorial(HabitRules.recent(habits, today: now, log: log, calendar: calendar))
                    }
                    todayList(habits, now: now, log: log)
                    VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                        VESSSectionHeader(title: "Last 4 weeks")
                        HabitGrid(levels: HabitRules.grid(habits, today: now, log: log, calendar: calendar))
                        ActivityFootnote(text: Text(HabitCopy.gridNote))
                    }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-habitsDemo") {
                        // DEBUG demo only, until the Insights method is decided.
                        VESSInsightCard(
                            kicker: Text("Pattern"),
                            text: Text(verbatim: "Water tends to reach your target on days you walk after lunch. A pattern, not a cause."),
                            linkTitle: "See insights"
                        )
                    }
                    #endif
                }
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    Button("Add a habit") { editing = HabitSheetRequest(habit: nil) }
                        .buttonStyle(habits.isEmpty ? .vessPrimary : .vessSecondary)
                        .accessibilityIdentifier("habits.add")
                    ActivityFootnote(text: Text(HabitCopy.noStreaks))
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(.fuel)
        .vessDetailTitle("Habits")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = HabitSheetRequest(habit: nil) } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a habit")
                .accessibilityIdentifier("habits.plus")
            }
        }
        .sheet(item: $editing) { request in
            AddHabitSheet(editing: request.habit)
        }
        // Success when a habit is added, also after the sheet has closed.
        .sensoryFeedback(.success, trigger: habits.count) { old, new in new > old }
        .navigationDestination(isPresented: $showEdit) {
            HabitEditList { editing = HabitSheetRequest(habit: $0) }
        }
        .vessErrorAlert(isPresented: $showError)
    }

    // MARK: Sections

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text("Small things, most days.")
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("Add a habit or two. Some track themselves from what you already log.")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "4/6 · HABITS TODAY · 2 left this evening".
    private func ring(_ status: HabitRules.DayStatus, now: Date) -> some View {
        let sublabel = HabitCopy.remaining(status, now: now, calendar: calendar)
        return VESSScoreRing(
            value: status.done.formatted(),
            unit: "/\(status.listed)",
            label: "Habits today",
            sublabel: sublabel,
            progress: status.share ?? 0,
            metric: .fuel
        )
        .frame(maxWidth: .infinity)
        // "4 of 6", not "4 slash 6".
        .accessibilityValue(Text("\(status.done) of \(status.listed), \(sublabel)"))
        .accessibilityIdentifier("habits.ring")
    }

    /// Calm words for the last seven days; never a judgement.
    private func editorial(_ recent: HabitRules.Recent) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Group {
                if recent.days == 0 {
                    Text("A fresh list.")
                } else if recent.mostDone * 2 > recent.days {
                    Text("Most days, most of the list.")
                } else if recent.mostDone > 0 {
                    Text("Some days, most of the list.")
                } else {
                    Text("Any day is a good day to pick it up.")
                }
            }
            .vessTextStyle(.editorialL)
            .foregroundStyle(VESSColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            Group {
                if recent.days == 0 {
                    Text("Your week fills in as you go.")
                } else {
                    Text("You finished most of your list on \(recent.mostDone) of the last ^[\(recent.days) day](inflect: true).")
                }
            }
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func todayList(_ habits: [Habit], now: Date, log: HabitRules.Log) -> some View {
        let listed = habits.filter { HabitRules.isListed($0, on: now, today: now, log: log, calendar: calendar) }
        return VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: "Today", actionTitle: "Edit", action: { showEdit = true })
            if listed.isEmpty {
                Text("Nothing on today's list.")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            } else {
                VESSRowGroup {
                    ForEach(listed) { habit in
                        row(habit, now: now, log: log)
                    }
                }
                .vessHairlineBottom()
            }
        }
    }

    private func row(_ habit: Habit, now: Date, log: HabitRules.Log) -> some View {
        let isDone = HabitRules.isComplete(habit, on: now, log: log, calendar: calendar)
        return VESSHabitRow(
            title: Text(verbatim: habit.name),
            subtitle: subtitle(habit, now: now, log: log),
            isDone: isDone,
            dots: HabitRules.marks(habit, today: now, log: log, calendar: calendar).map(\.dot),
            hue: habit.hue,
            onToggle: habit.auto == nil ? { toggle(habit, done: !HabitRules.isDone(habit, on: now, log: log, calendar: calendar), now: now) } : nil,
            spokenWeek: {
                guard case .timesPerWeek(let times) = habit.schedule else { return nil }
                return Text("\(HabitRules.weekCount(habit, through: now, log: log, calendar: calendar)) of \(times) this week")
            }()
        )
        .accessibilityIdentifier("habits.row.\(habit.name)")
    }

    /// "Daily · 08:00", "1 of 2 this week", "1.6 of 2.2 L · from your log".
    private func subtitle(_ habit: Habit, now: Date, log: HabitRules.Log) -> Text {
        let data = log.data[calendar.startOfDay(for: now)]
        switch habit.auto {
        case .waterTarget:
            let consumed = VESSFormat.liters(fromMilliliters: data?.hydrationMilliliters ?? 0)
            let target = VESSFormat.liters(fromMilliliters: data?.waterTargetMilliliters ?? 0)
            return Text("\(consumed) of \(target) L · from your log")
        case .proteinAtBreakfast:
            return Text("Daily · from your log")
        case .steps(let target):
            guard let steps = data?.steps else { return Text("From Apple Health, when connected") }
            return Text("\(VESSFormat.steps(Double(steps))) of \(VESSFormat.steps(Double(target))) · from Apple Health")
        case nil:
            break
        }
        if case .timesPerWeek(let times) = habit.schedule {
            return Text("\(HabitRules.weekCount(habit, through: now, log: log, calendar: calendar)) of \(times) this week")
        }
        let schedule = habit.schedule.title(calendar: calendar)
        guard let time = habit.reminder, let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: time.hour, minute: time.minute)) else {
            return schedule
        }
        return Text("\(schedule) · \(date, format: .dateTime.hour().minute())")
    }

    private func toggle(_ habit: Habit, done: Bool, now: Date) {
        do {
            try store.setHabit(habit.id, done: done, on: now, calendar: calendar)
            Task { await reminders.sync(store: store) }
        } catch {
            showError = true
        }
    }
}

struct HabitSheetRequest: Identifiable {
    let id = UUID()
    let habit: Habit?
}

// MARK: - Week strip

/// This week, one small neutral ring per day with its share of the list.
private struct HabitWeekStrip: View {
    let habits: [Habit]
    let today: Date
    let log: HabitRules.Log
    let calendar: Calendar

    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = 46
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var diameter: CGFloat { min(scaledDiameter, 48) }

    var body: some View {
        let todayStart = calendar.startOfDay(for: today)
        HStack(spacing: 0) {
            ForEach(HabitRules.week(containing: today, calendar: calendar), id: \.self) { day in
                let status = HabitRules.status(habits, on: day, today: today, log: log, calendar: calendar)
                let isFuture = day > todayStart
                VStack(spacing: VESSSpacing.xs) {
                    ZStack {
                        VESSRingShape(progress: shown ? (status.share ?? 0) : 0, tint: VESSColor.text,
                                      lineWidth: VESSRing.lineWidth(diameter: diameter, innerRadiusRatio: 0.88))
                        Text(day, format: .dateTime.day())
                            .vessTextStyle(.numberS)
                            .monospacedDigit()
                            .foregroundStyle(isFuture ? VESSColor.tertiaryText : VESSColor.text)
                    }
                    .frame(width: diameter, height: diameter)
                    Text(day, format: .dateTime.weekday(.narrow))
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
                .accessibilityValue(isFuture ? Text("Later this week") : Text("\(status.done) of \(status.listed) done"))
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear { withAnimation(reduceMotion ? nil : VESSMotion.ringSweep) { shown = true } }
    }
}

// MARK: - Grid

/// Four weeks of squares in four greyscale levels; later days are outlines.
private struct HabitGrid: View {
    let levels: [[Int?]]

    var body: some View {
        VStack(spacing: VESSSpacing.xs) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, week in
                HStack(spacing: VESSSpacing.xs) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, level in
                        let shape = RoundedRectangle(cornerRadius: VESSRadius.small, style: .continuous)
                        Group {
                            if let level {
                                shape.fill(Self.fill(level))
                            } else {
                                shape.strokeBorder(VESSColor.divider)
                            }
                        }
                        // Square, seven across the full width (reference 14).
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 4 weeks")
        .accessibilityValue(Text("\(levels.joined().filter { ($0 ?? 0) == 3 }.count) days with most of the list done"))
    }

    /// Stronger means more of the list was done.
    static func fill(_ level: Int) -> Color {
        switch level {
        case 1: VESSColor.borderStrong
        case 2: VESSColor.decorative
        case 3: VESSColor.secondaryText
        default: VESSColor.chartTrack
        }
    }
}

// MARK: - Edit list

/// Every habit; tap one to edit or delete it.
struct HabitEditList: View {
    @Environment(LocalStore.self) private var store
    let onSelect: (Habit) -> Void

    private let calendar = Calendar.current

    var body: some View {
        ProfilePage(title: "Edit habits") {
            VESSRowGroup {
                ForEach(store.habits) { habit in
                    Button { onSelect(habit) } label: {
                        VESSListRow(
                            title: Text(verbatim: habit.name),
                            subtitle: Text("\(habit.schedule.title(calendar: calendar)) · \(Text(habit.category.title))")
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .vessHairlineBottom()
        }
    }
}

// MARK: - Today row

/// "Habits · 4 of 6 today", shown on Today once there's a habit.
struct TodayHabitsRow: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    let now: Date
    let action: () -> Void

    var body: some View {
        let calendar = Calendar.current
        let habits = store.habits
        let log = HabitLogLoader.log(store: store, health: health.state.snapshot,
                                     from: HabitRules.week(containing: now, calendar: calendar).first ?? now, through: now, calendar: calendar)
        let status = HabitRules.status(habits, on: now, today: now, log: log, calendar: calendar)
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: "Habits")
            Button {
                action()
            } label: {
                VESSListRow(title: Text("\(status.done) of \(status.listed) today"), subtitle: HabitCopy.remaining(status, now: now, calendar: calendar))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .vessHairlineBottom()
            .accessibilityIdentifier("today.habits")
        }
    }
}

#if DEBUG
#Preview("Habits · Dark") {
    let store = LocalStore.preview()
    try? MockData.seedHabits(into: store, now: AppClock.now, calendar: .current)
    return NavigationStack { HabitsView() }
        .previewEnvironment(store)
        .preferredColorScheme(.dark)
}
#endif
