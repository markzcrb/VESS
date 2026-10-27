#if DEBUG
import SwiftUI

/// Every design system token and component on one screen, for checking Dark,
/// Light and Dynamic Type in Xcode Previews against
/// `Redesign/Design/components/*.png`. Values follow `Redesign/docs/DATA.md`.
/// Not shipped.
private struct DesignSystemGallery: View {
    /// Which slice to show; `nil` shows everything. Previews can't scroll,
    /// so each page fits roughly one screen.
    var page: Int?

    @State private var range = 0
    @State private var collection = 0
    @State private var weight = "78.4"
    @State private var allergies: Set<Allergen> = [.nuts]
    @State private var goal: WellnessGoal? = .maintainWeight

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.section) {
                    if shows(0) {
                        header
                        strip
                        VESSScoreRing(value: "78", label: "Fuel", sublabel: Text("3 of 4 meals logged"), progress: 0.78)
                            .frame(maxWidth: .infinity)
                        Text("A steady day. Protein is the one to watch.")
                            .vessTextStyle(.editorialL)
                            .foregroundStyle(VESSColor.text)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        metricRows
                    }
                    if shows(1) {
                        statusRows
                        VESSInsightCard(text: Text("Protein is at 108 of 140 g, and 70% of it came after noon. A protein-led dinner closes the gap."))
                        macroBars
                        impactRows
                    }
                    if shows(2) {
                        meals
                        controls
                        tags
                        inputs
                    }
                    if shows(3) {
                        buttons
                        typeScale
                    }
                    if shows(4) {
                        calendarDays
                        habitRows
                        pickTiles
                    }
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.bottom, 140)
            }
            .vessScreenBackground(.fuel)
            .vessDetailTitle("Design system", subtitle: Text("Tokens and components"))
        }
    }

    private func shows(_ index: Int) -> Bool {
        page == nil || page == index
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            Text(verbatim: "Tuesday, 6 October")
                .vessTextStyle(.labelCapsS)
                .foregroundStyle(VESSColor.secondaryText)
            Text(verbatim: "Good evening, Mark")
                .vessTextStyle(.titleL)
                .foregroundStyle(VESSColor.text)
        }
    }

    private var strip: some View {
        VESSMetricStrip {
            VESSMetricStripItem(value: "78", label: "Fuel", progress: 0.78, metric: .fuel)
            VESSMetricStripItem(value: "77", label: "Energy", progress: 0.77, metric: .energy)
            VESSMetricStripItem(value: "77", label: "Protein", progress: 0.77, metric: .protein)
            VESSMetricStripItem(value: "73", label: "Water", progress: 0.73, metric: .water)
            VESSMetricStripItem(value: "—", label: "Steps", progress: 0, metric: .activity)
        }
    }

    private var metricRows: some View {
        VStack(spacing: VESSSpacing.sm + 2) {
            VESSRowGroup {
                VESSMetricRow(systemImage: "flame", label: "Energy", value: "1,840", trend: .up)
                VESSMetricRow(systemImage: "fish", label: "Protein", value: "108 g", trend: .down)
                VESSMetricRow(systemImage: "leaf", label: "Fibre", value: "21 g", trend: .flat)
                VESSMetricRow(systemImage: "drop", label: "Hydration", value: "1.6 L", trend: .up)
            }
            VESSLegendChip()
        }
    }

    private var statusRows: some View {
        VESSRowGroup {
            VESSStatusRow(systemImage: "flame", label: "Energy vs. target", value: "77%", level: .sufficient)
            VESSStatusRow(systemImage: "clock", label: "Meal regularity", value: "92%", level: .optimal)
            VESSStatusRow(systemImage: "sun.max", label: "Before noon", value: "34%", level: .poor)
        }
    }

    private var macroBars: some View {
        VStack(spacing: 22) {
            VESSMacroBar(name: "Protein", value: "+31 g", target: "→ 139 / 140 g", logged: 108.0 / 140, adding: 31.0 / 140, metric: .protein)
            VESSMacroBar(name: "Carbs", value: "+12 g", target: "→ 208 / 260 g", logged: 196.0 / 260, adding: 12.0 / 260, metric: .carbs)
            VESSMacroBar(name: "Water", value: "1.6", target: "/ 2.2 L", adding: 0.73, metric: .water)
        }
    }

    private var impactRows: some View {
        VStack(spacing: VESSSpacing.xs) {
            VESSImpactRow(label: "Drank 2 L or more", impactPercent: 24)
            VESSImpactRow(label: "Ate fish", impactPercent: 2, isNew: true)
            VESSImpactRow(label: "Late dinner", impactPercent: -11)
        }
    }

    private var meals: some View {
        VStack(spacing: 0) {
            VESSSectionHeader(title: "Meals", actionTitle: "Diary", action: {})
            VESSRowGroup {
                VESSMealRow(time: time(7, 45), title: Text(verbatim: "Breakfast"), detail: Text(verbatim: "Greek yogurt, oats, blueberries"), calories: "520")
                VESSMealRow(time: time(16, 10), title: Text(verbatim: "Snack"), detail: Text(verbatim: "Skyr, pumpkin seeds, apple"), calories: "210")
                VESSMealRow(time: time(19, 30), title: Text(verbatim: "Dinner · planned"), detail: Text(verbatim: "Miso-glazed cod, bok choy, rice"), calories: "620", isPlanned: true)
                VESSListRow(systemImage: "calendar", title: Text(verbatim: "Plan ready · 2,350 kcal"), subtitle: Text(verbatim: "Overnight oats · Tuna niçoise · Prawn curry"))
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSegmented(selection: $range, options: [(0, "Day"), (1, "Week"), (2, "Month")])
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VESSSpacing.xs) {
                    VESSChip(title: "Recent", isSelected: collection == 0) { collection = 0 }
                    VESSChip(title: "Saved meals", isSelected: collection == 1) { collection = 1 }
                    VESSChip(title: "Favourites", isSelected: collection == 2) { collection = 2 }
                }
            }
            HStack {
                VESSIconButton(systemImage: "plus", label: "Add") {}
                VESSIconButton(systemImage: "checkmark", label: "Added", isFilled: true) {}
                VESSHeaderAddButton(label: "Add to dinner") {}
            }
        }
    }

    private var tags: some View {
        HStack(spacing: VESSSpacing.xs) {
            VESSTag(text: Text("Recorded"), tone: .positive)
            VESSTag(text: Text("Entered"))
            VESSTag(text: Text("Missing"), tone: .warning)
            VESSTag(text: Text("Use by Thu"), tone: .accent)
        }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSTextField("Weight", text: $weight, unit: "kg")
                .keyboardType(.decimalPad)
            VESSChipFlow {
                ForEach(Allergen.allCases, id: \.self) { allergen in
                    VESSChip(title: allergen.title, isSelected: allergies.contains(allergen)) {
                        allergies.formSymmetricDifference([allergen])
                    }
                }
            }
            VESSOptionRow(title: "Maintain weight", isSelected: goal == .maintainWeight) { goal = .maintainWeight }
            VESSOptionRow(title: "Eat healthier", detail: "More whole foods", isSelected: goal == .eatHealthier) { goal = .eatHealthier }
            VESSVesselLine(value: 0.73, tint: VESSColor.water, segments: 9)
        }
    }

    private var buttons: some View {
        VStack(spacing: VESSSpacing.sm) {
            Button("Add to dinner · 312 kcal") {}
                .buttonStyle(.vessPrimary)
            Button("Log a workout") {}
                .buttonStyle(.vessSecondary)
            HStack {
                Button("+250 ml") {}
                    .buttonStyle(.vessQuick)
                Spacer()
                Button("Add to dinner") {}
                    .buttonStyle(.vessQuiet)
            }
            Button("Disabled") {}
                .buttonStyle(.vessPrimary)
                .disabled(true)
        }
    }

    private var typeScale: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            ForEach(Array(Self.scale.enumerated()), id: \.offset) { _, item in
                Text(verbatim: item.sample)
                    .vessTextStyle(item.style)
                    .foregroundStyle(VESSColor.text)
            }
            Text("Tertiary text, at least 4.5:1")
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
        }
    }

    private static let scale: [(style: VESSTextStyle, sample: String)] = [
        (.displayHero, "78"), (.displayL, "312"), (.displayM, "1,840"), (.titleL, "Good evening, Mark"),
        (.numberRow, "108 g"), (.numberS, "620 kcal"), (.bodyM, "Protein is on track for today"),
        (.bodyMStrong, "Miso-glazed cod with greens"), (.bodyS, "Saved meal · 3 items"), (.caption, "Last synced 17:12"),
        (.labelCaps, "Heart of the breakdown"), (.labelCapsS, "Refreshed daily"), (.labelCapsLink, "Break down my day"),
        (.editorialL, "A steady day."), (.editorialM, "Holding steady inside your range."),
    ]

    /// CalendarDay: Default, Muted, Logged, Estimated, Today, and a logged today.
    private var calendarDays: some View {
        let day = AppClock.now
        let other = calendar.date(byAdding: .month, value: -1, to: day) ?? day
        return VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSSectionHeader(title: "Calendar day")
            HStack(spacing: 0) {
                VESSCalendarDay(date: day)
                VESSCalendarDay(date: other, state: .muted)
                VESSCalendarDay(date: day, state: .logged)
                VESSCalendarDay(date: day, state: .estimated)
                VESSCalendarDay(date: day, isToday: true)
                VESSCalendarDay(date: day, state: .logged, isToday: true)
            }
            VESSScoreRing(value: "14", label: "Cycle day", sublabel: Text(verbatim: "Next period in about 13 days"), progress: 14 / 29, metric: .cycle)
                .frame(maxWidth: .infinity)
        }
    }

    /// HabitRow: done and not done, auto-tracked and manual, every dot state.
    private var habitRows: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            VESSSectionHeader(title: "Habit row")
            VESSRowGroup {
                VESSHabitRow(title: Text(verbatim: "Protein at breakfast"), subtitle: Text(verbatim: "Daily · from your log"), isDone: true,
                             dots: [.done, .done, .notDone, .done, .future, .future, .future], hue: VESSColor.protein)
                VESSHabitRow(title: Text(verbatim: "Walk after lunch"), subtitle: Text(verbatim: "Weekdays · 15 min"), isDone: true,
                             dots: [.notDone, .done, .done, .done, .future, .future, .future], hue: VESSColor.activity, onToggle: {})
                VESSHabitRow(title: Text(verbatim: "Water 2.2 L"), subtitle: Text(verbatim: "1.6 of 2.2 L · from your log"), isDone: false,
                             dots: [.done, .notDone, .done, .open, .future, .future, .future], hue: VESSColor.water)
                VESSHabitRow(title: Text(verbatim: "Screens off by 23:00"), subtitle: Text(verbatim: "Daily · evening"), isDone: false,
                             dots: [.done, .done, .notDone, .open, .future, .future, .future], onToggle: {})
            }
            .vessHairlineBottom()
        }
    }

    /// PickTile: four across, one selected (Add › Drink, Add › Workout).
    private var pickTiles: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Pick tile")
            LazyVGrid(columns: VESSPickTile.columns(for: .large), spacing: VESSSpacing.xs) {
                VESSPickTile(title: Text(verbatim: "Water"), systemImage: "drop", isSelected: true) {}
                VESSPickTile(title: Text(verbatim: "Sparkling"), systemImage: "humidity", isSelected: false) {}
                VESSPickTile(title: Text(verbatim: "Espresso"), systemImage: "cup.and.heat.waves", isSelected: false) {}
                VESSPickTile(title: Text(verbatim: "More"), systemImage: "ellipsis", isSelected: false) {}
            }
        }
    }

    private func time(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: AppClock.now) ?? AppClock.now
    }
}

#Preview("Dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}

#Preview("Dark · 2") {
    DesignSystemGallery(page: 1)
        .preferredColorScheme(.dark)
}

#Preview("Dark · 3") {
    DesignSystemGallery(page: 2)
        .preferredColorScheme(.dark)
}

#Preview("Dark · 4") {
    DesignSystemGallery(page: 3)
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    DesignSystemGallery()
        .preferredColorScheme(.light)
}

#Preview("Light · 2") {
    DesignSystemGallery(page: 1)
        .preferredColorScheme(.light)
}

#Preview("AX5") {
    DesignSystemGallery(page: 0)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("AX5 · 3") {
    DesignSystemGallery(page: 2)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Dark · 5 (cycle, habits)") {
    DesignSystemGallery(page: 4)
        .preferredColorScheme(.dark)
}

#Preview("Light · 5 (cycle, habits)") {
    DesignSystemGallery(page: 4)
        .preferredColorScheme(.light)
}

#Preview("AX5 · 5 (cycle, habits)") {
    DesignSystemGallery(page: 4)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
#endif
