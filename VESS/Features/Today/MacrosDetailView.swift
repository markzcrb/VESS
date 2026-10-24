import SwiftUI

/// Macros (03): protein, carbs and fat against their targets for a day, or
/// as daily averages over the last week or month, plus the energy split and
/// protein over the week. Pushed from Today and Nutrition.
struct MacrosDetailView: View {
    enum Range: Hashable {
        case day, week, month

        var days: Int {
            switch self {
            case .day: 1
            case .week: 7
            case .month: 30
            }
        }
    }

    @Environment(LocalStore.self) private var store
    @State private var range: Range = .day
    @State private var showInfo = false

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if let profile = store.profile {
                content(profile: profile, now: AppClock.now)
            }
        }
        .vessScreenBackground(.protein)
        .vessDetailTitle("Macros")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("How this is measured", systemImage: "info.circle") { showInfo = true }
            }
        }
        .sheet(isPresented: $showInfo) { MacrosInfoSheet() }
    }

    private func content(profile: UserProfile, now: Date) -> some View {
        let targets = profile.nutritionTargets
        let start = calendar.date(byAdding: .day, value: -(Range.month.days - 1), to: calendar.startOfDay(for: now)) ?? now
        // The whole of today, as on Today and Nutrition.
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let entries = store.foodEntries(from: start, to: end)
        let totals = IntakeAnalysis.dailyTotals(entries, endingOn: now, days: range.days, calendar: calendar)
        let protein = IntakeAnalysis.average(totals, \.proteinGrams) ?? 0
        let carbs = IntakeAnalysis.average(totals, \.carbohydrateGrams) ?? 0
        let fat = IntakeAnalysis.average(totals, \.fatGrams) ?? 0
        let calories = IntakeAnalysis.average(totals, \.calories) ?? 0
        let week = IntakeAnalysis.dailyTotals(entries, endingOn: now, days: 7, calendar: calendar)
        let todayEntries = entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: now) }

        return ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                VESSSegmented(selection: $range, options: [(.day, "Day"), (.week, "Week"), (.month, "Month")])

                MacroRings(
                    protein: fraction(protein, targets.proteinGrams),
                    carbs: fraction(carbs, targets.carbohydrateGrams),
                    fat: fraction(fat, targets.fatGrams),
                    calories: calories,
                    isAverage: range != .day
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 22) {
                    VESSMacroBar(name: "Protein", value: VESSFormat.grams(protein), target: "/ \(VESSFormat.grams(targets.proteinGrams)) g", adding: fraction(protein, targets.proteinGrams), metric: .protein)
                    VESSMacroBar(name: "Carbs", value: VESSFormat.grams(carbs), target: "/ \(VESSFormat.grams(targets.carbohydrateGrams)) g", adding: fraction(carbs, targets.carbohydrateGrams), metric: .carbs)
                    VESSMacroBar(name: "Fat", value: VESSFormat.grams(fat), target: "/ \(VESSFormat.grams(targets.fatGrams)) g", adding: fraction(fat, targets.fatGrams), metric: .fat)
                }

                if let split = IntakeAnalysis.energySplit(proteinGrams: protein, carbGrams: carbs, fatGrams: fat) {
                    EnergyShare(split: split, target: IntakeAnalysis.energySplit(
                        proteinGrams: targets.proteinGrams, carbGrams: targets.carbohydrateGrams, fatGrams: targets.fatGrams
                    ))
                }

                if range == .day, let text = Self.insight(entries: todayEntries, profile: profile, now: now, calendar: calendar) {
                    VESSInsightCard(text: Text(text), linkTitle: nil)
                }

                proteinThisWeek(week: week, target: targets.proteinGrams)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.huge)
        }
    }

    private func proteinThisWeek(week: [IntakeAnalysis.DayTotal], target: Double) -> some View {
        let hits = week.filter { $0.hasEntries && $0.nutrition.proteinGrams >= target }.count
        let logged = week.filter(\.hasEntries).count
        let average = IntakeAnalysis.average(week, \.proteinGrams)

        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Protein this week")
            VESSWeekBars(
                bars: week.map { .init(day: $0.day, value: $0.nutrition.proteinGrams) },
                target: target,
                targetLabel: "\(VESSFormat.grams(target)) g",
                tint: VESSColor.protein
            )
            if let average {
                Text("Hit target on \(hits) of \(logged) days. Average \(VESSFormat.grams(average)) g.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.text)
            }
        }
    }

    private func fraction(_ value: Double, _ target: Double) -> Double {
        target > 0 ? value / target : 0
    }

    /// "Carbs and fat are on pace. Protein is 32 g short with dinner still to
    /// come." Only facts from today's log; `nil` before anything is logged.
    static func insight(entries: [FoodLogEntry], profile: UserProfile, now: Date, calendar: Calendar) -> String? {
        guard !entries.isEmpty else { return nil }
        let summary = DaySummary(
            entries: entries, hydrationLogs: [], targets: profile.nutritionTargets,
            waterTargetMilliliters: profile.waterTargetMilliliters, day: now, now: now, calendar: calendar
        )
        let floor = max(summary.expectedPace, DaySummary.minimumPace) * DaySummary.behindThreshold
        let consumed = summary.consumed, targets = summary.targets
        let carbsOnPace = targets.carbohydrateGrams > 0 && consumed.carbohydrateGrams / targets.carbohydrateGrams >= floor
        let fatOnPace = targets.fatGrams > 0 && consumed.fatGrams / targets.fatGrams >= floor
        let proteinShort = targets.proteinGrams - consumed.proteinGrams

        var parts: [String] = []
        switch (carbsOnPace, fatOnPace) {
        case (true, true): parts.append(String(localized: "Carbs and fat are on pace."))
        case (true, false): parts.append(String(localized: "Carbs are on pace; fat is lighter so far."))
        case (false, true): parts.append(String(localized: "Fat is on pace; carbs are lighter so far."))
        case (false, false): parts.append(String(localized: "Carbs and fat are lighter so far."))
        }
        if proteinShort > 0 {
            let dinnerToCome = entries.entries(for: .dinner).isEmpty
                && calendar.component(.hour, from: now) < MealType.dinner.suggestionEndHour
            parts.append(dinnerToCome
                ? String(localized: "Protein is \(VESSFormat.grams(proteinShort)) g short with dinner still to come.")
                : String(localized: "Protein is \(VESSFormat.grams(proteinShort)) g short of your target."))
        } else {
            parts.append(String(localized: "Protein has reached your target."))
        }
        return parts.joined(separator: " ")
    }
}

/// Three concentric rings: protein outside, carbs, fat inside, with energy in the centre.
private struct MacroRings: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    let calories: Double
    let isAverage: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let diameter = VESSSize.heroRing
        let width = VESSRing.lineWidth(diameter: diameter)
        let gap = width + 6

        ZStack {
            ring(protein, VESSColor.protein, diameter: diameter, width: width)
            ring(carbs, VESSColor.carbs, diameter: diameter - gap * 2, width: width)
            ring(fat, VESSColor.fat, diameter: diameter - gap * 4, width: width)
            VStack(spacing: VESSSpacing.xxs) {
                Text(VESSFormat.calories(calories))
                    .vessTextStyle(.displayM)
                    .foregroundStyle(VESSColor.text)
                    .contentTransition(.numericText())
                Text(isAverage ? "kcal a day" : "kcal")
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { withAnimation(reduceMotion ? nil : VESSMotion.ringSweep) { shown = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Macros")
        .accessibilityValue(Text("Protein \(percent(protein)), carbs \(percent(carbs)), fat \(percent(fat)) of target. \(VESSFormat.calories(calories)) kcal."))
    }

    private func ring(_ value: Double, _ tint: Color, diameter: CGFloat, width: CGFloat) -> some View {
        VESSRingShape(progress: shown ? value : 0, tint: tint, lineWidth: width)
            .frame(width: diameter, height: diameter)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// "Share of energy": a three-part bar with each macro's share, and the
/// split the targets imply.
private struct EnergyShare: View {
    let split: IntakeAnalysis.EnergySplit
    let target: IntakeAnalysis.EnergySplit?

    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 6

    var body: some View {
        let parts: [(LocalizedStringResource, Double, Color)] = [
            ("Protein", split.protein, VESSColor.protein),
            ("Carbs", split.carbs, VESSColor.carbs),
            ("Fat", split.fat, VESSColor.fat),
        ]

        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Share of energy")
            GeometryReader { proxy in
                HStack(spacing: 4) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        Capsule()
                            .fill(part.2)
                            .frame(width: max(barHeight, (proxy.size.width - 8) * part.1))
                    }
                }
            }
            .frame(height: barHeight)
            .accessibilityHidden(true)
            HStack(alignment: .top) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    VStack(alignment: index == 0 ? .leading : (index == 1 ? .leading : .trailing), spacing: VESSSpacing.xxs) {
                        Text(part.1.formatted(.percent.precision(.fractionLength(0))))
                            .vessTextStyle(.numberRow)
                            .foregroundStyle(VESSColor.text)
                        HStack(spacing: VESSSpacing.xs - 2) {
                            Circle().fill(part.2).frame(width: 6, height: 6).accessibilityHidden(true)
                            Text(part.0)
                                .vessTextStyle(.bodyS)
                                .foregroundStyle(VESSColor.secondaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if index < parts.count - 1 { Spacer(minLength: VESSSpacing.xs) }
                }
            }
            if let target {
                Text("Target split is \(Self.whole(target.protein)) / \(Self.whole(target.carbs)) / \(Self.whole(target.fat)).")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
    }

    private static func whole(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))"
    }
}

/// How the Macros screen's numbers are worked out.
private struct MacrosInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                    Text("How macros are measured")
                        .vessTextStyle(.editorialM)
                        .foregroundStyle(VESSColor.text)
                    Text("Day shows what you've logged today. Week and Month show daily averages over the days with at least one meal logged.")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Share of energy counts 4 kcal per gram of protein and carbs and 9 kcal per gram of fat. The target split comes from your daily targets.")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Foods that don't report a macro add nothing to it, so totals can read low.")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
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
}

#if DEBUG
#Preview("Macros · Dark") {
    NavigationStack { MacrosDetailView() }
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
#endif
