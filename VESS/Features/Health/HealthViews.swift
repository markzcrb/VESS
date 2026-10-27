import SwiftUI

// MARK: - H00 Health hub

/// Sleep, Heart, Stress and Body at a glance, and what VESS reads from
/// Apple Health. Reached from You › Health and the Today metric strip.
struct HealthHubView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let snapshot = health.state.snapshot
        let readings = snapshot.map { HealthReadings(snapshot: $0, now: now, calendar: calendar) }

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                ProfileIntro(title: "How your body is doing.", text: "Read from Apple Health. Nothing here is a diagnosis.")

                // The last sync failed: the values shown are the last known ones.
                if case .failed(let lastKnown) = health.state {
                    VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                        Text(lastKnown.map { "Couldn't reach Apple Health. Showing what was read at \($0.updatedAt.formatted(date: .omitted, time: .shortened))." }
                             ?? String(localized: "Couldn't reach Apple Health."))
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.warningText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Retry") {
                            Task { await health.refresh(stepsTarget: store.profile?.dailyStepsTarget ?? UserProfile.defaultStepsTarget) }
                        }
                        .buttonStyle(.vessQuick)
                        .accessibilityIdentifier("health.hub.retry")
                    }
                }

                let sleep = tile(.sleep, HealthTile(
                    systemImage: "moon", iconTint: VESSColor.sleep, label: "Sleep",
                    value: Text(verbatim: readings?.lastNight.map { HealthFormat.duration(minutes: $0.asleepMinutes) } ?? "—"),
                    caption: caption(readings?.lastNight != nil, kinds: [.sleep], normal: Text("Last night"), empty: Text("No sleep recorded"))
                ))
                let heart = tile(.heart, HealthTile(
                    systemImage: "heart", iconTint: VESSColor.heart, label: "Heart",
                    value: readings?.restingToday.map { Text("\(HealthFormat.whole($0))\u{00A0}bpm") } ?? Text(verbatim: "—"),
                    caption: caption(readings?.restingToday != nil, kinds: [.restingHeartRate], normal: Text("Resting"), empty: Text("No data today"))
                ))
                let stress = tile(.stress, stressTile(readings?.stress))
                let bodyLink = tile(.body, bodyTile(snapshot: snapshot, now: now))
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: VESSSpacing.sm) {
                        sleep
                        heart
                        stress
                        bodyLink
                    }
                } else {
                    // A Grid, so both tiles in a row are as tall as the taller one.
                    Grid(horizontalSpacing: VESSSpacing.sm, verticalSpacing: VESSSpacing.sm) {
                        GridRow {
                            sleep
                            heart
                        }
                        GridRow {
                            stress
                            bodyLink
                        }
                    }
                }

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSSectionHeader(title: "From Apple Health")
                    VESSRowGroup {
                        permission("Sleep analysis", hasData: !(snapshot?.sleep.isEmpty ?? true))
                        permission("Heart rate, resting, HRV", hasData: !(snapshot?.restingHeartRate.isEmpty ?? true) || !(snapshot?.heartRateVariability.isEmpty ?? true))
                        permission("State of Mind", hasData: !(snapshot?.stateOfMind.isEmpty ?? true))
                        permission("Mindful minutes", hasData: snapshot?.mindfulMinutesToday != nil)
                    }
                    .vessHairlineBottom()
                }

                if case .notConnected = health.state, health.canConnect {
                    Button("Connect Apple Health") {
                        Task { await health.connect(stepsTarget: store.profile?.dailyStepsTarget ?? UserProfile.defaultStepsTarget) }
                    }
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("health.hub.connect")
                }

                ActivityFootnote(text: Text("Without an Apple Watch, Sleep and Heart show only what your iPhone or other apps save to Health. VESS doesn't guess missing values."))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(.fuel)
        .vessDetailTitle("Health")
        .toolbar(.hidden, for: .tabBar)
    }

    /// The tile's caption; with no value, "Not shared" when Health isn't
    /// sharing that kind, else the empty text.
    private func caption(_ hasValue: Bool, kinds: [HealthDataKind], normal: Text, empty: Text) -> Text {
        if hasValue { return normal }
        return HealthAccessRow.isShown(health.state, kinds: kinds) ? Text("Not shared · check access") : empty
    }

    private func tile(_ route: HealthRoute, _ content: HealthTile) -> some View {
        NavigationLink(value: route) { content }
            .buttonStyle(.plain)
    }

    private func stressTile(_ estimate: StressRules.Estimate?) -> HealthTile {
        switch estimate {
        case .estimate(let today, _):
            HealthTile(systemImage: "waveform.path.ecg", iconTint: VESSColor.water, label: "Stress", value: Text(today.title), caption: Text("Today, so far"))
        case .building(let days):
            HealthTile(systemImage: "waveform.path.ecg", iconTint: VESSColor.water, label: "Stress", value: Text(verbatim: "—"),
                       caption: Text("Building your baseline · \(days) of \(StressRules.minimumDays) days"))
        case nil:
            HealthTile(systemImage: "waveform.path.ecg", iconTint: VESSColor.water, label: "Stress", value: Text(verbatim: "—"),
                       caption: caption(false, kinds: [.heartRateVariability, .restingHeartRate], normal: Text(verbatim: ""), empty: Text("No data today")))
        }
    }

    private func bodyTile(snapshot: HealthSnapshot?, now: Date) -> HealthTile {
        guard let profile = store.profile else {
            return HealthTile(systemImage: "scalemass", iconTint: VESSColor.secondaryText, label: "Body", value: Text(verbatim: "—"), caption: Text("Weight"))
        }
        let weight = BodyRules.weight(profile: profile, health: snapshot?.latestWeight)
        if BodyRules.showsBMI(profile: profile, now: now, calendar: calendar), let bmi = BodyRules.bmi(profile: profile, health: snapshot?.latestWeight) {
            return HealthTile(
                systemImage: "scalemass", iconTint: VESSColor.secondaryText, label: "Body",
                value: Text(verbatim: bmi.formatted(.number.precision(.fractionLength(1)))),
                caption: Text("BMI · \(VESSFormat.quantity(weight))\u{00A0}kg")
            )
        }
        return HealthTile(systemImage: "scalemass", iconTint: VESSColor.secondaryText, label: "Body",
                          value: Text("\(VESSFormat.quantity(weight))\u{00A0}kg"), caption: Text("Weight"))
    }

    /// iOS doesn't tell apps what they may read, so the status says what
    /// VESS sees: data, or none yet.
    private func permission(_ title: LocalizedStringResource, hasData: Bool) -> some View {
        let status: Text = switch health.state {
        case .notConnected: Text("Not connected")
        default: hasData ? Text("Allowed") : Text("No data")
        }
        return NavigationLink(value: HealthRoute.appleHealth) {
            VESSListRow(title: Text(title), value: status)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - H01 Sleep

/// Last night against the user's sleep target, stages when an Apple Watch
/// recorded them, 7 nights, and a pattern once there is one.
struct SleepView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    @State private var editsTarget = false
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let readings = health.state.snapshot.map { HealthReadings(snapshot: $0, now: now, calendar: calendar) }
        let target = store.profile?.dailySleepTargetMinutes ?? UserProfile.defaultSleepTargetMinutes
        let night = readings?.lastNight

        HealthPage(
            title: "Sleep", metric: .sleep, infoLabel: "About sleep",
            info: HealthInfoSheet(title: "How Sleep is read", notes: [
                "Last night is your main sleep that ended between 03:00 and 14:00 today. Naps don't count.",
                "When your Apple Watch and another app both recorded the same time, the Watch is used.",
                "Your usual is the middle value of the 28 nights before. The ring fills toward your sleep target.",
                "Stages come from Apple Watch only. VESS doesn't diagnose sleep problems.",
            ])
        ) {
            VESSScoreRing(
                value: night.map { HealthFormat.duration(minutes: $0.asleepMinutes) } ?? "—",
                label: "Sleep",
                sublabel: Text("Last night · Apple Health"),
                progress: (night?.asleepMinutes ?? 0) / Double(target),
                metric: .sleep,
                emptyCaption: Text("No sleep recorded last night")
            )
            .frame(maxWidth: .infinity)

            HealthAccessRow(kinds: [.sleep], what: String(localized: "sleep"))

            if let line = readings.flatMap(editorial) {
                Text(line)
                    .vessTextStyle(.editorialM)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let night { stages(night) }

            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                VESSSectionHeader(
                    title: "Last 7 nights",
                    detail: readings?.weekAverage.map { Text("Average \(HealthFormat.duration(minutes: $0))") }
                )
                if readings?.weekAverage == nil {
                    HealthEmptyLine(text: Text("Nights appear here once Apple Health has sleep data. Sleep needs Apple Watch or a sleep app."))
                } else {
                    HealthWeekBars(days: readings?.week ?? [], metric: .sleep)
                }
                VESSRowGroup {
                    Button { editsTarget = true } label: {
                        VESSListRow(title: Text("Sleep target"), value: Text(verbatim: HealthFormat.hours(minutes: target)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sleep.target")
                }
                .vessHairlineBottom()
            }

            if let readings, let pattern = TrendRule.lateDinnerSleep(
                nights: readings.nights, entries: patternEntries(now: now), now: now, calendar: calendar
            ) {
                HealthPatternCard(text: Text("On nights you ate within 2 hours of falling asleep, you slept about \(pattern.minutesLess)\u{00A0}min less. A pattern from \(pattern.weeks) weeks, not a cause."))
            }

            ActivityFootnote(text: Text("Read from Apple Health. VESS doesn't keep a copy and doesn't diagnose sleep problems."))
        }
        .sheet(isPresented: $editsTarget) {
            NumberEditSheet(title: "Sleep target", unit: "h", value: Double(target) / 60, range: 4...12, step: 0.5, fractionDigits: 1) { hours in
                guard var profile = store.profile else { return }
                profile.sleepTargetMinutes = Int((hours * 60).rounded())
                do { try store.saveProfile(profile) } catch { showError = true }
            }
        }
        .vessErrorAlert(isPresented: $showError)
    }

    /// "Close to your usual 7 h 20. You fell asleep 40 min later than usual."
    private func editorial(_ readings: HealthReadings) -> String? {
        guard readings.lastNight != nil, let usual = readings.usualSleepMinutes, let difference = readings.sleepDifference else { return nil }
        let usualText = HealthFormat.duration(minutes: usual)
        var line: String
        if abs(difference) < 15 {
            line = String(localized: "Close to your usual \(usualText).")
        } else if difference < 0 {
            line = String(localized: "About \(HealthFormat.duration(minutes: -difference)) less than your usual \(usualText).")
        } else {
            line = String(localized: "About \(HealthFormat.duration(minutes: difference)) more than your usual \(usualText).")
        }
        if let bedtime = readings.bedtimeDifference, abs(bedtime) >= 20 {
            let minutes = HealthFormat.duration(minutes: abs(bedtime))
            line += " " + (bedtime > 0
                ? String(localized: "You fell asleep \(minutes) later than usual.")
                : String(localized: "You fell asleep \(minutes) earlier than usual."))
        }
        return line
    }

    @ViewBuilder
    private func stages(_ night: SleepRules.Night) -> some View {
        let range = "\(night.start.formatted(date: .omitted, time: .shortened)) \u{2013} \(night.end.formatted(date: .omitted, time: .shortened))"
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSSectionHeader(title: "Stages · \(range)", detail: night.isWatch ? Text("Apple Watch") : nil)
            if night.hasStages {
                SleepStagesBar(stages: night.stages)
                VESSRowGroup {
                    ForEach(SleepStagesBar.order, id: \.self) { stage in
                        if let minutes = night.stages[stage] {
                            VESSListRow(title: Text(SleepStagesBar.title(stage)), value: Text(verbatim: HealthFormat.duration(minutes: minutes)), showsChevron: false)
                        }
                    }
                }
                .vessHairlineBottom()
            } else {
                Text("Stages need Apple Watch. This night shows the time in bed or asleep that Health has.")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Food entries over the nights the pattern looks at.
    private func patternEntries(now: Date) -> [FoodLogEntry] {
        let start = calendar.date(byAdding: .day, value: -HealthKitService.sleepDays, to: calendar.startOfDay(for: now)) ?? now
        return store.foodEntries(from: start, to: now)
    }
}

/// Deep, core, REM and awake, side by side by share of the night.
struct SleepStagesBar: View {
    let stages: [SleepSample.Stage: Double]

    static let order: [SleepSample.Stage] = [.deep, .core, .rem, .awake]

    static func title(_ stage: SleepSample.Stage) -> LocalizedStringResource {
        switch stage {
        case .deep: "Deep"
        case .core: "Core"
        case .rem: "REM"
        case .awake: "Awake"
        case .asleep: "Asleep"
        case .inBed: "In bed"
        }
    }

    var body: some View {
        let parts = Self.order.compactMap { stage in stages[stage].map { (stage, $0) } }
        let total = max(parts.reduce(0) { $0 + $1.1 }, 1)

        GeometryReader { proxy in
            let gaps = CGFloat(max(parts.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(parts, id: \.0) { stage, minutes in
                    Capsule()
                        .fill(fill(stage))
                        .frame(width: max((proxy.size.width - gaps) * minutes / total, 4))
                }
            }
        }
        .frame(height: VESSSpacing.md + 2)
        .accessibilityHidden(true)
    }

    private func fill(_ stage: SleepSample.Stage) -> Color {
        switch stage {
        case .deep: VESSColor.sleep.opacity(0.55)
        case .core: VESSColor.sleep.opacity(0.75)
        case .rem: VESSColor.sleep
        default: VESSColor.chartMuted
        }
    }
}

// MARK: - H02 Heart

/// Today's resting heart rate within the user's usual range (the middle
/// 80 % of 30 days; not a score), HRV, walking heart rate and today's range.
struct HeartView: View {
    @Environment(HealthDataStore.self) private var health

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let snapshot = health.state.snapshot
        let readings = snapshot.map { HealthReadings(snapshot: $0, now: now, calendar: calendar) }

        HealthPage(
            title: "Heart", metric: .heart, infoLabel: "About heart",
            info: HealthInfoSheet(title: "How Heart is read", notes: [
                "The ring shows where today's resting heart rate sits within your usual range: the middle 80\u{00A0}% of your last 30 days. It isn't a score.",
                "Heart rate variability is the overnight value Apple Watch records, compared with your 30-day average.",
                "For information only, not a medical device. If you feel unwell or notice unusual readings, talk to a doctor.",
            ])
        ) {
            VESSScoreRing(
                value: readings?.restingToday.map(HealthFormat.whole) ?? "—",
                unit: readings?.restingToday == nil ? nil : "bpm",
                label: "Resting",
                sublabel: readings?.restingUsual.map { Text("Today · your usual \(HealthFormat.range($0))") } ?? Text("Today"),
                progress: readings.flatMap { r in r.restingToday.flatMap { today in r.restingUsual.map { HeartRules.ringFraction(today, in: $0) } } } ?? 0,
                metric: .heart,
                emptyCaption: Text("No resting heart rate recorded today")
            )
            .frame(maxWidth: .infinity)

            HealthAccessRow(kinds: [.restingHeartRate, .heartRateVariability, .heartRate], what: String(localized: "heart data"))

            if let line = readings.flatMap(editorial) {
                Text(line)
                    .vessTextStyle(.editorialM)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let readings {
                VESSRowGroup {
                    if let resting = readings.restingToday {
                        VESSListRow(title: Text("Resting heart rate"), subtitle: readings.restingAverage.map { Text("30-day average \(HealthFormat.whole($0))") },
                                    value: Text("\(HealthFormat.whole(resting))\u{00A0}bpm"), showsChevron: false)
                    }
                    if let hrv = readings.hrvToday {
                        VESSListRow(title: Text("Heart rate variability"), subtitle: readings.hrvAverage.map { Text("30-day average \(HealthFormat.whole($0))\u{00A0}ms") },
                                    value: Text("\(HealthFormat.whole(hrv))\u{00A0}ms"), showsChevron: false)
                    }
                    if let walking = readings.walkingToday {
                        VESSListRow(title: Text("Walking heart rate"), subtitle: Text("Average while walking"),
                                    value: Text("\(HealthFormat.whole(walking))\u{00A0}bpm"), showsChevron: false)
                    }
                    if let range = readings.rangeToday {
                        VESSListRow(title: Text("Range today"), subtitle: Text("Lowest and highest"),
                                    value: Text("\(HealthFormat.range(range))\u{00A0}bpm"), showsChevron: false)
                    }
                }
                .vessHairlineBottom()
            }

            if let hours = snapshot?.heartRateToday, !hours.isEmpty {
                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    VESSSectionHeader(title: "Today · hourly range")
                    HeartHourlyRange(hours: hours, now: now, calendar: calendar)
                }
            }

            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                VESSSectionHeader(title: "Resting · last 7 days")
                if let readings, readings.restingWeek.contains(where: { $0.value != nil }) {
                    // From 40 bpm, so day-to-day differences are visible.
                    HealthWeekBars(days: readings.restingWeek, metric: .heart, baseline: 40)
                } else {
                    HealthEmptyLine(text: Text("Days appear here once Apple Health has heart data. Resting heart rate needs Apple Watch."))
                }
            }

            ActivityFootnote(text: Text("Read from Apple Health. For information only, not a medical device. If you feel unwell or notice unusual readings, talk to a doctor."))
        }
    }

    /// "Resting heart rate is in your usual range. HRV is a little below your 30-day average."
    private func editorial(_ readings: HealthReadings) -> String? {
        var parts: [String] = []
        switch readings.restingComparison {
        case .close: parts.append(String(localized: "Resting heart rate is in your usual range."))
        case .below, .aLittleBelow: parts.append(String(localized: "Resting heart rate is below your usual range."))
        case .above, .aLittleAbove: parts.append(String(localized: "Resting heart rate is above your usual range."))
        case nil: break
        }
        if let hrv = readings.hrvComparison {
            parts.append(String(localized: "HRV is \(hrv.phrase) your 30-day average."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Today's heart rate, lowest to highest per hour, 00:00 to now. The
/// current hour in the heart hue, earlier hours softer.
struct HeartHourlyRange: View {
    let hours: [HourlyRange]
    let now: Date
    let calendar: Calendar

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120

    var body: some View {
        let low = (hours.map(\.min).min() ?? 0) - 5
        let high = max((hours.map(\.max).max() ?? 1), low + 1)
        let lastHour = calendar.component(.hour, from: now)

        VStack(spacing: VESSSpacing.xs) {
            GeometryReader { proxy in
                let slot = proxy.size.width / CGFloat(max(lastHour + 1, 1))
                ForEach(hours, id: \.start) { hour in
                    let index = calendar.component(.hour, from: hour.start)
                    let top = proxy.size.height * (1 - (hour.max - low) / (high - low))
                    let bottom = proxy.size.height * (1 - (hour.min - low) / (high - low))
                    Capsule()
                        .fill(index == lastHour ? VESSColor.heart : VESSColor.heart.opacity(0.5))
                        .frame(width: min(slot * 0.6, VESSSpacing.md), height: max(bottom - top, VESSSpacing.xs))
                        .position(x: slot * (CGFloat(index) + 0.5), y: (top + bottom) / 2)
                }
            }
            .frame(height: height)
            HStack {
                Text(verbatim: "00")
                Spacer()
                if lastHour >= 9 {
                    Text(verbatim: "06")
                    Spacer()
                }
                if lastHour >= 15 {
                    Text(verbatim: "12")
                    Spacer()
                }
                Text("Now")
            }
            .vessTextStyle(.labelCapsS)
            .foregroundStyle(VESSColor.tertiaryText)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityHidden(true)
    }
}

// MARK: - H03 Stress

/// An estimate from overnight HRV and resting heart rate against the user's
/// own 28-day baseline. Never red, never a medical measurement. State of
/// Mind and mindful minutes are shown as signals and never change it.
struct StressView: View {
    @Environment(HealthDataStore.self) private var health

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let snapshot = health.state.snapshot
        let readings = snapshot.map { HealthReadings(snapshot: $0, now: now, calendar: calendar) }

        HealthPage(
            title: "Stress", metric: .water, infoLabel: "About this estimate",
            info: HealthInfoSheet(title: "How the estimate works", notes: [
                "Your baseline is the middle value of 28 days of overnight HRV and resting heart rate. It needs 14 days before there's an estimate.",
                "Elevated: HRV at least 15\u{00A0}% below your baseline and resting heart rate at least 5\u{00A0}% above. High: at least 30\u{00A0}% and 10\u{00A0}%.",
                "Parts of the day compare that part's HRV with your baseline.",
                "State of Mind and mindful minutes are shown as signals. They don't change the estimate.",
                "An estimate, not a medical measurement.",
            ])
        ) {
            ring(readings?.stress)
                .frame(maxWidth: .infinity)

            HealthAccessRow(kinds: [.heartRateVariability, .restingHeartRate], what: String(localized: "heart data"))

            if case .estimate(let today, let parts) = readings?.stress {
                Text(editorial(today: today, parts: parts))
                    .vessTextStyle(.editorialM)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                StressParts(parts: parts)
            }

            if let snapshot, let readings {
                signals(snapshot: snapshot, readings: readings)
            }

            if let readings, let pattern = TrendRule.shortSleepAfternoons(
                nights: readings.nights, afternoons: readings.pastAfternoons, now: now, calendar: calendar
            ) {
                HealthPatternCard(text: Text("Over the last 5 weeks, \(pattern.afterShort) of \(pattern.elevated) elevated afternoons came after a night with under 6\u{00A0}h of sleep. A pattern, not a cause."))
            }

            ActivityFootnote(text: Text("An estimate from Apple Watch data compared with your own baseline, not a medical measurement. If stress feels hard to manage, talk to someone you trust or a professional."))
        }
    }

    @ViewBuilder
    private func ring(_ estimate: StressRules.Estimate?) -> some View {
        switch estimate {
        case .estimate(let today, _):
            VESSScoreRing(value: String(localized: today.title), label: "Today, so far", sublabel: Text("From HRV and resting heart rate"),
                          progress: today.ringFraction, metric: .water)
        case .building(let days):
            VESSScoreRing(value: "—", label: "Building your baseline", sublabel: Text("\(days) of \(StressRules.minimumDays) days"),
                          progress: Double(days) / Double(StressRules.minimumDays), metric: .water)
        case nil:
            VESSScoreRing(value: "—", label: "Today, so far", progress: 0, metric: .water,
                          emptyCaption: Text("Needs today's HRV and resting heart rate from Apple Watch"))
        }
    }

    /// "Your body signals look close to your baseline. The afternoon was more strained than the morning."
    private func editorial(today: StressRules.Level, parts: [StressRules.PartOfDay: StressRules.Level]) -> String {
        var line = switch today {
        case .calm: String(localized: "Your body signals look close to your baseline.")
        case .elevated: String(localized: "Your body signals are a little further from your baseline than usual.")
        case .high: String(localized: "Your body signals are further from your baseline than usual.")
        }
        let ordered = StressRules.PartOfDay.allCases.filter { parts[$0] != nil }
        if let strained = ordered.first(where: { parts[$0] != .calm }), let calm = ordered.first(where: { parts[$0] == .calm }) {
            line += " " + String(localized: "The \(strained.inSentence) was more strained than the \(calm.inSentence).")
        }
        return line
    }

    private func signals(snapshot: HealthSnapshot, readings: HealthReadings) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            VESSSectionHeader(title: "Signals")
            VESSRowGroup {
                if let hrv = readings.hrvToday {
                    VESSListRow(title: Text("Heart rate variability"),
                                subtitle: readings.hrvComparison.map { Text($0.signal) },
                                value: Text("\(HealthFormat.whole(hrv))\u{00A0}ms"), showsChevron: false)
                }
                if let resting = readings.restingToday {
                    VESSListRow(title: Text("Resting heart rate"), subtitle: restingSubtitle(readings.restingComparison),
                                value: Text("\(HealthFormat.whole(resting))\u{00A0}bpm"), showsChevron: false)
                }
                if let night = readings.lastNight {
                    VESSListRow(title: Text("Sleep last night"), subtitle: sleepSubtitle(readings.sleepDifference),
                                value: Text(verbatim: HealthFormat.duration(minutes: night.asleepMinutes)), showsChevron: false)
                }
                if let mindful = snapshot.mindfulMinutesToday {
                    VESSListRow(title: Text("Mindful minutes"), subtitle: Text("From Apple Health"),
                                value: Text(verbatim: HealthFormat.duration(minutes: mindful)), showsChevron: false)
                }
                if let mood = snapshot.stateOfMind.last(where: { calendar.isDate($0.date, inSameDayAs: AppClock.now) }) {
                    VESSListRow(title: Text("State of Mind"),
                                subtitle: Text("Logged at \(mood.date, format: .dateTime.hour().minute()) · Apple Health"),
                                value: Text(Self.valence(mood.value)), showsChevron: false)
                }
            }
            .vessHairlineBottom()
        }
    }

    private func restingSubtitle(_ comparison: HeartRules.Comparison?) -> Text? {
        switch comparison {
        case .close: Text("In your usual range")
        case .below, .aLittleBelow: Text("Below your usual range")
        case .above, .aLittleAbove: Text("Above your usual range")
        case nil: nil
        }
    }

    private func sleepSubtitle(_ difference: Double?) -> Text? {
        guard let difference else { return nil }
        if difference <= -60 { return Text("Shorter than usual") }
        if difference <= -15 { return Text("A little short") }
        if difference >= 15 { return Text("Longer than usual") }
        return Text("About usual")
    }

    /// State of Mind valence (−1…1) in words.
    private static func valence(_ value: Double) -> LocalizedStringResource {
        switch value {
        case ..<(-0.2): "Unpleasant"
        case ...0.2: "Neutral"
        default: "Pleasant"
        }
    }
}

/// Morning · afternoon · evening, so far today. A part that hasn't come yet
/// shows "—"; a strained one is tinted, never red.
struct StressParts: View {
    let parts: [StressRules.PartOfDay: StressRules.Level]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: VESSSpacing.xs))
            : AnyLayout(HStackLayout(spacing: VESSSpacing.xs))

        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSSectionHeader(title: "Today · by part of day")
            layout {
                ForEach(StressRules.PartOfDay.allCases, id: \.self) { part in
                    let level = parts[part]
                    VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                        Text(part.title)
                            .vessTextStyle(.labelCapsS)
                            .foregroundStyle(VESSColor.secondaryText)
                        Text(level.map { $0.title } ?? "—")
                            .vessTextStyle(.bodyMStrong)
                            .foregroundStyle(VESSColor.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(VESSSpacing.sm)
                    .background(level == nil || level == .calm ? VESSColor.fill : VESSColor.tintWater,
                                in: RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
