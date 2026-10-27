import Charts
import SwiftUI

/// Caffeine for a day: what was logged against the 400 mg daily limit, an
/// estimate of what's still in the body (5-hour half-life) with the amount at
/// 22:00, and a grid to log a caffeinated drink in one tap. Reached from
/// Nutrition › Drinks and from the Add a drink sheet.
struct CaffeineView: View {
    let day: Date

    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showError = false
    /// One height for every symbol, so titles line up across tiles.
    @ScaledMetric(relativeTo: .body) private var iconHeight: CGFloat = 22

    private let calendar = Calendar.current

    /// Every drink with caffeine, in catalog order.
    /// The offered drinks with caffeine, in the sheet's order (cola is no
    /// longer offered, so it doesn't repeat the soft drink).
    private static let caffeinated = DrinkCategory.allCases.flatMap(\.presets).filter { $0.caffeineMilligramsPer100Milliliters > 0 }

    var body: some View {
        let now = AppClock.now
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        // The evening before still counts toward what's in the body.
        let logs = store.hydrationLogs(from: start.addingTimeInterval(-24 * 3600), to: end)
        let dayLogs = logs.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) && $0.caffeineMilligrams > 0 }
        let total = CaffeineModel.total(logs, on: day, calendar: calendar)
        let evening = CaffeineModel.evening(of: day, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                summary(total: total, isToday: isToday)
                inYourSystem(logs: logs, start: start, end: end, evening: evening, now: isToday ? now : nil)
                quickLog(isToday: isToday)
                if !dayLogs.isEmpty {
                    VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                        VESSSectionHeader(title: isToday ? "Today's caffeine" : "That day's caffeine")
                        VESSRowGroup {
                            ForEach(dayLogs.sorted { $0.loggedAt > $1.loggedAt }) { log in
                                DrinkLogRow(log: log, value: .caffeine)
                            }
                        }
                        .vessHairlineBottom()
                    }
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(.carbs)
        .vessDetailTitle("Caffeine")
        .toolbar(.hidden, for: .tabBar)
        .vessErrorAlert(isPresented: $showError)
    }

    // MARK: Sections

    /// The ring: mg logged against the limit. Above it, a calm line.
    private func summary(total: Double, isToday: Bool) -> some View {
        let limit = CaffeineModel.dailyLimitMilligrams
        return VStack(spacing: VESSSpacing.lg) {
            VESSScoreRing(
                value: VESSFormat.grams(total),
                unit: "mg",
                label: "Caffeine",
                sublabel: Text("of \(VESSFormat.grams(limit))\u{00A0}mg \(isToday ? Text("today") : Text("that day"))"),
                progress: min(CaffeineModel.limitShare(of: total), 1),
                metric: .carbs
            )
            if total > limit {
                Text("\(VESSFormat.grams(total - limit))\u{00A0}mg above the \(VESSFormat.grams(limit))\u{00A0}mg daily limit.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The decay curve, a line at now, and "≈ N mg in your system at 22:00".
    private func inYourSystem(logs: [HydrationLog], start: Date, end: Date, evening: Date, now: Date?) -> some View {
        let chartStart = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: start) ?? start
        let points = CaffeineModel.curve(logs, from: chartStart, to: end)
        let atEvening = CaffeineModel.remaining(logs, at: evening)
        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "In your system")
            CaffeineCurve(points: points, start: chartStart, end: end, evening: evening, now: now)
                .accessibilityRepresentation {
                    Text("Estimated caffeine in your system through the day")
                        .accessibilityValue(Text(now.map { "Now about \(VESSFormat.grams(CaffeineModel.remaining(logs, at: $0)))\u{00A0}mg; " } ?? "")
                            + Text("about \(VESSFormat.grams(atEvening))\u{00A0}mg at 22:00"))
                }
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                Text("≈\u{00A0}\(VESSFormat.grams(atEvening))\u{00A0}mg in your system at \(evening, format: .dateTime.hour().minute())")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.text)
                Text("An estimate: caffeine halves about every \(VESSFormat.quantity(CaffeineModel.halfLifeHours)) hours, and this differs from person to person.")
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }

    /// One tap logs a typical serving now (noon for an earlier day).
    private func quickLog(isToday: Bool) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: VESSSpacing.sm), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
        return VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSSectionHeader(title: "Log caffeine")
            LazyVGrid(columns: columns, spacing: VESSSpacing.sm) {
                ForEach(Self.caffeinated, id: \.self) { preset in
                    tile(preset)
                }
            }
            Text("Typical values for a standard serving.")
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
        }
    }

    private func tile(_ preset: DrinkPreset) -> some View {
        let volume = preset.defaultVolumeMilliliters
        let milligrams = preset.caffeineMilligramsPer100Milliliters * volume / 100
        let shape = RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous)
        return Button {
            log(preset)
        } label: {
            // Icon and "+" on top, so the name and amounts get the full width
            // and never break mid-word.
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                HStack {
                    Image(systemName: preset.symbol)
                        .foregroundStyle(VESSColor.secondaryText)
                        .frame(height: iconHeight)
                    Spacer(minLength: VESSSpacing.sm)
                    Image(systemName: "plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VESSColor.tertiaryText)
                }
                .accessibilityHidden(true)
                Text(preset.title)
                    .vessTextStyle(.bodyMStrong)
                    .foregroundStyle(VESSColor.text)
                // Non-breaking spaces keep "250 ml" and "125 mg" whole.
                Text("\(VESSFormat.milliliters(volume))\u{00A0}ml · \(VESSFormat.grams(milligrams))\u{00A0}mg")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(VESSSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(minHeight: VESSHitTarget.minimum)
            .background(VESSColor.fill, in: shape)
            .overlay(shape.strokeBorder(VESSColor.divider))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(preset.title)), \(VESSFormat.milliliters(volume))\u{00A0}ml, \(VESSFormat.grams(milligrams))\u{00A0}mg caffeine"))
        .accessibilityHint("Logs it")
        .accessibilityIdentifier("caffeine.log.\(preset.rawValue)")
    }

    // MARK: Actions

    private func log(_ preset: DrinkPreset) {
        guard let profile = store.profile else { return }
        let volume = preset.defaultVolumeMilliliters
        let drink = preset.drink(
            name: String(localized: preset.title),
            hydrationContributionPercent: DrinkFacts.contributionPercent(preset, profile: profile)
        )
        let log = drink.log(userID: profile.id, volumeMilliliters: volume, at: DrinkTime.defaultTime(on: day, calendar: calendar))
        do {
            try store.add(log)
            undo.show(Text("Added \(VESSFormat.milliliters(volume))\u{00A0}ml of \(drink.name)")) { store in
                try store.deleteHydrationLog(id: log.id)
            }
        } catch {
            showError = true
        }
    }
}

/// Estimated mg in the body through the day, in the caffeine hue, with a
/// line at now and a dot at 22:00. Draws left to right (Reduce Motion: at once).
private struct CaffeineCurve: View {
    let points: [CaffeineModel.Point]
    let start: Date
    let end: Date
    let evening: Date
    let now: Date?

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 180

    var body: some View {
        let peak = max(points.map(\.milligrams).max() ?? 0, 50)
        let atEvening = points.min { abs($0.date.timeIntervalSince(evening)) < abs($1.date.timeIntervalSince(evening)) }

        Chart {
            ForEach(points, id: \.date) { point in
                AreaMark(x: .value("Time", point.date), y: .value("Caffeine", point.milligrams))
                    .foregroundStyle(VESSColor.carbs.opacity(0.18))
                LineMark(x: .value("Time", point.date), y: .value("Caffeine", point.milligrams))
                    .foregroundStyle(VESSColor.carbs)
                    .lineStyle(StrokeStyle(lineWidth: 1.75))
            }
            if let now {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(VESSColor.decorative)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            if let atEvening {
                PointMark(x: .value("22:00", atEvening.date), y: .value("Caffeine", atEvening.milligrams))
                    .foregroundStyle(VESSColor.carbs)
                    .symbolSize(50)
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...(peak * 1.15))
        // Hour labels are placed from the plot frame below: the chart's own
        // date labels sit beside their ticks and drop 24.
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(VESSColor.chartGuide)
                AxisValueLabel {
                    if let mg = value.as(Double.self) {
                        Text("\(VESSFormat.grams(mg))\u{00A0}mg")
                            .vessTextStyle(.caption)
                            .foregroundStyle(VESSColor.tertiaryText)
                    }
                }
            }
        }
        .chartPlotStyle { plot in plot.modifier(LineDrawReveal()) }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    ForEach(hourMarks, id: \.hour) { mark in
                        if let x = proxy.position(forX: mark.date) {
                            Text(verbatim: String(format: "%02d", mark.hour))
                                .vessTextStyle(.caption)
                                .foregroundStyle(VESSColor.tertiaryText)
                                .fixedSize()
                                .position(x: frame.minX + x, y: frame.maxY + VESSSpacing.md)
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .padding(.bottom, VESSSpacing.lg)
        // Labels stop growing at accessibility sizes, like the other charts.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// 06, 12, 18 and 24 on the chart's day.
    private var hourMarks: [(hour: Int, date: Date)] {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: start)
        return [6, 12, 18, 24].compactMap { hour in
            calendar.date(byAdding: .hour, value: hour, to: midnight).map { (hour, $0) }
        }
    }
}

#if DEBUG
#Preview("Caffeine · Dark") {
    NavigationStack {
        CaffeineView(day: AppClock.now)
    }
    .previewEnvironment(LocalStore.preview())
    .preferredColorScheme(.dark)
}

#Preview("Caffeine · Light") {
    NavigationStack {
        CaffeineView(day: AppClock.now)
    }
    .previewEnvironment(LocalStore.preview())
    .preferredColorScheme(.light)
}
#endif
