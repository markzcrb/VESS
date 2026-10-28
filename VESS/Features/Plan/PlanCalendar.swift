import SwiftUI

/// Week plans for any range of days, for the strip, the month grid and the
/// selected day's line (17, 18). Reads only: nothing new is stored.
struct PlanCalendarData {
    let store: LocalStore
    let calendar: Calendar

    /// The plan of the week that contains `day`.
    func week(containing day: Date, now: Date) -> WeekPlan {
        let start = calendar.startOfWeek(for: day)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return WeekPlan(
            weekStart: start,
            entries: store.foodEntries(from: start, to: end),
            planned: store.plannedMeals(from: start, to: end),
            now: now, calendar: calendar
        )
    }

    func day(_ day: Date, now: Date) -> WeekPlan.Day? {
        week(containing: day, now: now).days.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// Always six weeks from the start of the week holding the 1st, so the
    /// grid never changes height between months.
    func monthDays(_ month: Date, now: Date) -> [WeekPlan.Day] {
        let first = calendar.dateInterval(of: .month, for: month)?.start ?? month
        var start = calendar.startOfWeek(for: first)
        var days: [WeekPlan.Day] = []
        for _ in 0..<6 {
            days += week(containing: start, now: now).days
            start = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        }
        return days
    }
}

extension WeekPlan.Coverage {
    var dot: VESSPlanDay.Dot {
        switch self {
        case .none: .none
        case .some: .some
        case .all: .all
        }
    }
}

extension WeekPlan.Day {
    /// Spoken after the date: "2 of 3 meals planned".
    var spokenStatus: Text {
        isPast
            ? Text("\(filledCount) of \(slots.count) meals logged")
            : Text("\(filledCount) of \(slots.count) meals planned")
    }
}

/// The week strip under the title (17): seven equal columns at every text
/// size (the days cap their own text, so Sunday never scrolls away); a
/// horizontal swipe changes week.
struct PlanWeekStrip: View {
    let days: [WeekPlan.Day]
    let selection: Date
    let calendar: Calendar
    let onSelect: (Date) -> Void
    let onSwipe: (Int) -> Void

    var body: some View {
            HStack(spacing: 0) {
                ForEach(days, id: \.date) { day in
                    cell(day)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        let dx = value.translation.width
                        guard abs(dx) > 50, abs(dx) > abs(value.translation.height) else { return }
                        onSwipe(dx < 0 ? 1 : -1)
                    }
            )
            .accessibilityAction(named: "Next week") { onSwipe(1) }
            .accessibilityAction(named: "Previous week") { onSwipe(-1) }
    }

    private func cell(_ day: WeekPlan.Day) -> some View {
        VESSPlanDay(
            date: day.date,
            dot: day.coverage.dot,
            isSelected: calendar.isDate(day.date, inSameDayAs: selection),
            isToday: day.isToday,
            spokenStatus: day.spokenStatus
        ) {
            onSelect(day.date)
        }
        .accessibilityIdentifier("plan.day.\(day.date.formatted(.dateTime.day()))")
    }
}

/// The month grid (18): weekday letters, six rows of days (outside the
/// month muted, no dot), then the legend.
struct PlanMonthGrid: View {
    let month: Date
    let selection: Date
    let calendar: Calendar
    let store: LocalStore
    let onSelect: (Date) -> Void

    var body: some View {
        let days = PlanCalendarData(store: store, calendar: calendar).monthDays(month, now: AppClock.now)
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VStack(spacing: VESSSpacing.xxs) {
                HStack(spacing: 0) {
                    ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                        Text(letter)
                            .vessTextStyle(.labelCapsS)
                            .foregroundStyle(VESSColor.tertiaryText)
                            .frame(maxWidth: .infinity)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityHidden(true)
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(days[(row * 7)..<min(row * 7 + 7, days.count)], id: \.date) { day in
                            let inMonth = calendar.isDate(day.date, equalTo: month, toGranularity: .month)
                            VESSPlanDay(
                                date: day.date,
                                dot: inMonth ? day.coverage.dot : .none,
                                isSelected: calendar.isDate(day.date, inSameDayAs: selection),
                                isToday: day.isToday,
                                isMuted: !inMonth,
                                showsWeekday: false,
                                spokenStatus: day.spokenStatus
                            ) {
                                onSelect(day.date)
                            }
                        }
                    }
                }
            }
            legend
        }
    }

    /// "M T W T F S S", starting on the locale's first weekday.
    private var weekdayLetters: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VESSSpacing.lg) { legendItems }
            VStack(alignment: .leading, spacing: VESSSpacing.xs) { legendItems }
        }
        .vessTextStyle(.bodyS)
        .foregroundStyle(VESSColor.tertiaryText)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var legendItems: some View {
        HStack(spacing: VESSSpacing.xs) {
            Circle().fill(VESSColor.secondaryText).frame(width: 5, height: 5)
            Text("All main meals")
        }
        HStack(spacing: VESSSpacing.xs) {
            Circle().strokeBorder(VESSColor.secondaryText, lineWidth: 1).frame(width: 5, height: 5)
            Text("Some")
        }
        HStack(spacing: VESSSpacing.xs) {
            Circle().strokeBorder(VESSColor.text, lineWidth: 1.5).frame(width: 12, height: 12)
            Text("Today")
        }
    }
}
