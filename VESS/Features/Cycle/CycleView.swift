import SwiftUI

/// 13: cycle tracking. Today's cycle day, when the next period is likely,
/// the month, today's log, and recent cycles. Opt-in from You; reached
/// from the Today row only while it's on.
struct CycleView: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo

    @State private var editingDay: EditingDay?
    @State private var showInfo = false
    @State private var showHistory = false
    @State private var showError = false
    /// Each inline change to today's log: one light tap.

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let days = store.cycleDays
        let summary = CyclePrediction.summary(days, today: now, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    ring(summary)
                    estimateText(summary)
                }
                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    VESSSectionHeader(
                        title: LocalizedStringResource(stringLiteral: now.formatted(.dateTime.month(.wide))),
                        actionTitle: "History",
                        action: { showHistory = true }
                    )
                    CycleMonthGrid(month: now, days: days, estimate: summary.estimate, today: now, calendar: calendar) { day in
                        editingDay = EditingDay(date: day)
                    }
                    CycleLegend()
                }
                logToday(now: now)
                recentCycles(summary)
                ActivityFootnote(text: Text(CycleCopy.disclaimer))
                    .accessibilityIdentifier("cycle.disclaimer")
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(.cycle)
        .vessDetailTitle("Cycle")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                VESSToolbarInfoButton(label: "About these estimates") { showInfo = true }
                    .accessibilityIdentifier("cycle.info")
            }
        }
        // A calendar day picked to edit.
        .vessHaptic(.selection, trigger: editingDay != nil) { _, new in new }
        .sheet(item: $editingDay) { day in
            CycleDaySheet(date: day.date)
        }
        .sheet(isPresented: $showInfo) {
            CycleInfoSheet()
        }
        .navigationDestination(isPresented: $showHistory) {
            CycleHistoryView()
        }
        .vessErrorAlert(isPresented: $showError)
    }

    private struct EditingDay: Identifiable {
        let date: Date
        var id: Date { date }
    }

    // MARK: Sections

    private func ring(_ summary: CyclePrediction.Summary) -> some View {
        let progress: Double = if let day = summary.cycleDay, let estimate = summary.estimate {
            Double(day) / Double(max(estimate.averageDays, 1))
        } else {
            0
        }
        return VESSScoreRing(
            value: summary.cycleDay.map { $0.formatted() } ?? "—",
            label: "Cycle day",
            // The long "Log three period starts…" line is the editorial below.
            sublabel: summary.estimate == nil ? Text("No estimate yet") : CycleCopy.nextText(summary),
            progress: progress,
            metric: .cycle
        )
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("cycle.ring")
    }

    /// The editorial line and how the estimate was made.
    private func estimateText(_ summary: CyclePrediction.Summary) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Group {
                if let estimate = summary.estimate {
                    if summary.isPastWindow {
                        Text("Your period may come later than estimated.")
                    } else {
                        Text("Next period likely \(CycleCopy.window(estimate, calendar: calendar)).")
                    }
                } else if CycleCopy.isAllExcluded(summary) {
                    Text("No estimate yet.")
                } else {
                    Text("\(Text(CycleCopy.needsMore)).")
                }
            }
            .vessTextStyle(.editorialL)
            .foregroundStyle(VESSColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("cycle.estimate")

            Group {
                if let estimate = summary.estimate {
                    if estimate.isLessCertain {
                        Text("An estimate from your last ^[\(estimate.cycleCount) cycle](inflect: true), which vary by more than a week, so it's less certain than usual. It can be off.")
                    } else {
                        Text("An estimate from your last ^[\(estimate.cycleCount) cycle](inflect: true), which average \(estimate.averageDays) days. It can be off.")
                    }
                } else if CycleCopy.isAllExcluded(summary) {
                    Text(CycleCopy.allExcluded)
                } else {
                    Text("Tap a day in the calendar to log it, or use Period started today.")
                }
            }
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Flow and symptoms for today, saved as they're tapped.
    private func logToday(now: Date) -> some View {
        let today = store.cycleDay(on: now, calendar: calendar)
        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Log today")
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                Text("Flow")
                    .vessTextStyle(.labelCapsS)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .accessibilityHidden(true)
                CycleFlowChips(flow: todayBinding(now: now, \.flow, default: .none))
            }
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                Text("Symptoms")
                    .vessTextStyle(.labelCapsS)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .accessibilityHidden(true)
                CycleSymptomChips(symptoms: todayBinding(now: now, \.symptoms, default: []))
            }
            Button {
                editingDay = EditingDay(date: calendar.startOfDay(for: now))
            } label: {
                VESSListRow(title: Text("Note"), value: today?.note.map { Text(verbatim: $0) } ?? Text("Optional"))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .vessHairlineBottom()
            .accessibilityIdentifier("cycle.note")
            if !(today?.flow.isPeriod ?? false) {
                Button("Period started today") { periodStarted(now: now) }
                    .buttonStyle(.vessSecondary)
                    .padding(.top, VESSSpacing.xs)
                    .accessibilityIdentifier("cycle.periodStarted")
            }
        }
    }

    private func recentCycles(_ summary: CyclePrediction.Summary) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            VESSSectionHeader(title: "Recent cycles", actionTitle: summary.cycles.count > 3 ? "All" : nil, action: { showHistory = true })
            if summary.cycles.isEmpty {
                Text("Nothing logged yet. Tap a day in the calendar, or Period started today.")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VESSRowGroup {
                    ForEach(Array(summary.cycles.prefix(3).enumerated()), id: \.element.start) { _, cycle in
                        CycleRow(cycle: cycle, cycleDay: cycle.lengthDays == nil ? summary.cycleDay : nil)
                    }
                }
                .vessHairlineBottom()
                if let estimate = summary.estimate {
                    Text("Average \(estimate.averageDays) days · range \(estimate.shortestDays)–\(estimate.longestDays) days over ^[\(estimate.cycleCount) cycle](inflect: true).")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, VESSSpacing.xs)
                }
            }
        }
    }

    // MARK: Today's log

    /// Reads today's record and saves each change straight away.
    private func todayBinding<Value>(now: Date, _ keyPath: WritableKeyPath<CycleDay, Value>, default value: Value) -> Binding<Value> {
        Binding(
            get: { store.cycleDay(on: now, calendar: calendar)?[keyPath: keyPath] ?? value },
            set: { newValue in
                var day = store.cycleDay(on: now, calendar: calendar)
                    ?? CycleDay(id: UUID(), day: calendar.startOfDay(for: now), flow: .none, symptoms: [], note: nil)
                day[keyPath: keyPath] = newValue
                do {
                    try store.save(day, calendar: calendar)
                } catch {
                    showError = true
                }
            }
        )
    }

    /// Medium flow for today, which the chips can change.
    private func periodStarted(now: Date) {
        let before = store.cycleDay(on: now, calendar: calendar)
        var day = before ?? CycleDay(id: UUID(), day: calendar.startOfDay(for: now), flow: .none, symptoms: [], note: nil)
        day.flow = .medium
        do {
            try store.save(day, calendar: calendar)
            undo.show(Text("Period started today")) { [calendar] store in
                try store.deleteCycleDay(id: day.id)
                if let before { try store.save(before, calendar: calendar) }
            }
        } catch {
            showError = true
        }
    }
}

// MARK: - Month grid

/// A month, weeks in the calendar's order, always six rows so the height
/// doesn't jump. Past days and today open the day sheet.
struct CycleMonthGrid: View {
    let month: Date
    let days: [CycleDay]
    let estimate: CyclePrediction.Estimate?
    let today: Date
    let calendar: Calendar
    let onSelect: (Date) -> Void

    var body: some View {
        let periodDays = Set(days.filter { $0.flow.isPeriod }.map { calendar.startOfDay(for: $0.day) })
        let cells = Self.cells(for: month, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)

        VStack(spacing: VESSSpacing.xxs) {
            HStack(spacing: 0) {
                ForEach(Array(Self.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
            }
            .accessibilityHidden(true)
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(cells[(row * 7)..<(row * 7 + 7)], id: \.self) { date in
                        VESSCalendarDay(
                            date: date,
                            state: state(of: date, periodDays: periodDays, today: todayStart),
                            isToday: date == todayStart,
                            action: date <= todayStart ? { onSelect(date) } : nil
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(month, format: .dateTime.month(.wide).year()))
    }

    /// Logged first, then estimated (future days only), then outside the month.
    private func state(of date: Date, periodDays: Set<Date>, today: Date) -> VESSCalendarDay.State {
        if periodDays.contains(date) { return .logged }
        if let estimate, date > today, CyclePrediction.isInWindow(date, of: estimate, calendar: calendar) { return .estimated }
        if !calendar.isDate(date, equalTo: month, toGranularity: .month) { return .muted }
        return .default
    }

    /// 42 days from the start of the week holding the 1st.
    static func cells(for month: Date, calendar: Calendar) -> [Date] {
        let first = calendar.dateInterval(of: .month, for: month)?.start ?? calendar.startOfDay(for: month)
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: first) ?? first
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

/// Logged · Estimated · Today.
private struct CycleLegend: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var markSize: CGFloat = 10

    var body: some View {
        // One per line at accessibility sizes, so no word breaks.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xs))
            : AnyLayout(HStackLayout(spacing: VESSSpacing.md))
        layout {
            item(Circle().fill(VESSColor.cycle), "Logged")
            item(Circle().fill(VESSColor.tintCycle).overlay(Circle().strokeBorder(VESSColor.cycle, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))), "Estimated")
            item(Circle().strokeBorder(VESSColor.text, lineWidth: 1.5), "Today")
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Filled days are logged, dashed days are estimated, and the outlined day is today")
    }

    private func item(_ mark: some View, _ title: LocalizedStringResource) -> some View {
        HStack(spacing: VESSSpacing.xs - 2) {
            mark.frame(width: markSize, height: markSize)
            Text(title)
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.secondaryText)
        }
    }
}

/// "Started 1 October · Period 5 days · current" and "Day 6" or "29 days".
private struct CycleRow: View {
    let cycle: CyclePrediction.Cycle
    let cycleDay: Int?

    var body: some View {
        VESSRow(
            title: Text("Started \(cycle.start, format: .dateTime.day().month(.wide))"),
            subtitle: cycle.lengthDays == nil
                ? Text("Period ^[\(cycle.periodDays) day](inflect: true) · current")
                : Text("Period ^[\(cycle.periodDays) day](inflect: true)")
        ) {
            Group {
                if let length = cycle.lengthDays {
                    Text("^[\(length) day](inflect: true)")
                } else if let cycleDay {
                    Text("Day \(cycleDay)")
                }
            }
            .vessTextStyle(.bodyM)
            .foregroundStyle(VESSColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - History

/// Every cycle, and the months before this one.
struct CycleHistoryView: View {
    @Environment(LocalStore.self) private var store
    @State private var editingDate: EditingDate?

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let days = store.cycleDays
        let summary = CyclePrediction.summary(days, today: now, calendar: calendar)

        ProfilePage(title: "Cycle history") {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                VESSSectionHeader(title: "All cycles")
                if summary.cycles.isEmpty {
                    Text("Nothing logged yet.")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                } else {
                    VESSRowGroup {
                        ForEach(summary.cycles, id: \.start) { cycle in
                            CycleRow(cycle: cycle, cycleDay: cycle.lengthDays == nil ? summary.cycleDay : nil)
                        }
                    }
                    .vessHairlineBottom()
                }
                if summary.estimate == nil {
                    CycleCopy.noEstimateText(summary)
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, VESSSpacing.xs)
                }
            }
            ForEach(months(since: days.first?.day ?? now, now: now), id: \.self) { month in
                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    VESSSectionHeader(title: LocalizedStringResource(stringLiteral: month.formatted(.dateTime.month(.wide).year())))
                    CycleMonthGrid(month: month, days: days, estimate: summary.estimate, today: now, calendar: calendar) {
                        editingDate = EditingDate(date: $0)
                    }
                }
            }
            ActivityFootnote(text: Text(CycleCopy.disclaimer))
        }
        .sheet(item: $editingDate) { item in
            CycleDaySheet(date: item.date)
        }
    }

    private struct EditingDate: Identifiable {
        let date: Date
        var id: Date { date }
    }

    /// Last month back to the first logged month, newest first, at most a year.
    private func months(since first: Date, now: Date) -> [Date] {
        let start = calendar.dateInterval(of: .month, for: first)?.start ?? first
        return (1...12).compactMap { calendar.date(byAdding: .month, value: -$0, to: now) }
            .filter { $0 >= start || calendar.isDate($0, equalTo: start, toGranularity: .month) }
    }
}

// MARK: - Info

/// How the estimate works, and what it isn't.
struct CycleInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                HStack(alignment: .top) {
                    Text("About these estimates")
                        .vessTextStyle(.titleL)
                        .foregroundStyle(VESSColor.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: VESSSpacing.md)
                    VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
                ForEach(Array(Self.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ActivityFootnote(text: Text(CycleCopy.disclaimer))
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.vertical, VESSSpacing.xl)
        }
        .background(VESSColor.card)
        // Full height: at half height the last paragraphs were cut off.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    private static let paragraphs: [LocalizedStringResource] = [
        "A cycle runs from the first day of one period to the first day of the next. VESS uses your last six completed cycles.",
        "The window runs from your shortest to your longest of those cycles. It says when they vary by more than a week.",
        "Log three period starts to see an estimate: that's two completed cycles.",
        "Cycles shorter than 15 or longer than 60 days are left out, as they usually mean a period wasn't logged. If every cycle is left out, there's no estimate yet.",
        "VESS doesn't estimate fertile days or ovulation, and the estimate can't be used to prevent or plan a pregnancy.",
    ]
}

// MARK: - Today row

/// Today's cycle row: "Cycle day 6 · Next period in about 24 days".
/// Shown only while cycle tracking is on.
struct TodayCycleRow: View {
    @Environment(LocalStore.self) private var store
    let now: Date
    /// "Log ›": the Add sheet on Cycle.
    var onLog: (() -> Void)?
    let action: () -> Void

    var body: some View {
        let summary = CyclePrediction.summary(store.cycleDays, today: now, calendar: .current)
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: "Cycle", actionTitle: onLog == nil ? nil : "Log", action: onLog)
            Button {
                action()
            } label: {
                VESSListRow(
                    title: summary.cycleDay.map { Text("Cycle day \($0)") } ?? Text("Cycle"),
                    subtitle: CycleCopy.nextText(summary)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .vessHairlineBottom()
            .accessibilityIdentifier("today.cycle")
        }
    }
}

#if DEBUG
#Preview("Cycle · Dark") {
    let store = LocalStore.preview()
    try? MockData.cycleDays(now: AppClock.now, calendar: .current).forEach { try store.save($0, calendar: .current) }
    return NavigationStack { CycleView() }
        .previewEnvironment(store)
        .preferredColorScheme(.dark)
}

#Preview("Cycle · Light") {
    let store = LocalStore.preview()
    try? MockData.cycleDays(now: AppClock.now, calendar: .current).forEach { try store.save($0, calendar: .current) }
    return NavigationStack { CycleView() }
        .previewEnvironment(store)
        .preferredColorScheme(.light)
}

#Preview("Cycle · Empty") {
    NavigationStack { CycleView() }
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
#endif
