import SwiftUI

/// 10: log a drink. The day's hydration, the drink, a size, then Add.
/// "Custom" opens G01 for any amount; the time row changes when it was drunk.
/// The volume drunk and the share counted toward water are stored apart.
struct AddDrinkSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let day: Date
    @State private var preset: DrinkPreset = .water
    /// The amount to add: a card's size, or a drink's typical serving.
    @State private var volume: Double = DrinkSize.mug.milliliters
    @State private var time = AppClock.now
    @State private var showTime = false
    @State private var showCustom = false
    @State private var showCaffeine = false
    @State private var showError = false
    @State private var hasLoaded = false

    private let calendar = Calendar.current

    var body: some View {
        let logs = store.hydrationLogs(on: day, calendar: calendar)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    header(logs: logs)
                    DrinkChoice(preset: preset) { option in
                        preset = option
                        volume = option.defaultVolumeMilliliters
                    }
                    VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                        sizeCards
                        DrinkTimeRow(time: $time, isExpanded: $showTime, range: DrinkTime.range(on: day, calendar: calendar))
                    }
                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        VESSSectionHeader(title: isToday ? "Today" : "That day")
                        HydrationTimeline(logs: logs, now: isToday ? AppClock.now : nil, calendar: calendar)
                    }
                    todayList(logs)
                    caffeineLink(logs)
                    footnote
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.xl)
            }
            .background(VESSColor.card)
            .safeAreaInset(edge: .bottom) { addButton }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showCaffeine) {
                CaffeineView(day: day)
            }
            .navigationDestination(isPresented: $showCustom) {
                CustomDrinkView(day: day, preset: preset, volume: volume, time: time, onClose: { dismiss() })
            }
            .vessErrorAlert(isPresented: $showError, retry: add)
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                time = DrinkTime.defaultTime(on: day, calendar: calendar)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    // MARK: Sections

    /// HYDRATION, "1.6 of 2.2 L", close, and the water line.
    private func header(logs: [HydrationLog]) -> some View {
        let hydration = summary(logs)
        return VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text("Hydration")
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    if let hydration {
                        VESSMetric(
                            value: Text(VESSFormat.liters(fromMilliliters: hydration.consumedMilliliters)),
                            context: Text("of \(VESSFormat.liters(fromMilliliters: hydration.targetMilliliters)) L")
                        )
                        .foregroundStyle(VESSColor.text)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: VESSSpacing.md)
                VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
            }
            if let hydration {
                VESSVesselLine(value: hydration.fractionComplete, tint: VESSColor.water)
            }
        }
    }

    /// Glass, Mug, Can, Bottle and a small Custom card in one row (reference
    /// 10). From the xxLarge text size up, five no longer fit the width, so
    /// they wrap into two columns.
    @ViewBuilder
    private var sizeCards: some View {
        if dynamicTypeSize <= .xLarge {
            HStack(alignment: .top, spacing: VESSSpacing.xs) {
                ForEach(DrinkSize.allCases, id: \.self) { sizeCard($0) }
                customCard
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: VESSSpacing.sm), GridItem(.flexible(), spacing: VESSSpacing.sm)], spacing: VESSSpacing.sm) {
                ForEach(DrinkSize.allCases, id: \.self) { sizeCard($0) }
                customCard
            }
        }
    }

    private func sizeCard(_ option: DrinkSize) -> some View {
        let isSelected = option.milliliters == volume
        return Button {
            volume = option.milliliters
        } label: {
            DrinkCardLabel(symbol: option.symbol, isSelected: isSelected) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xxs) {
                    Text(verbatim: VESSFormat.milliliters(option.milliliters))
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                    Text("ml")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                }
                Text(option.title)
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(option.title)), \(VESSFormat.milliliters(option.milliliters)) ml"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("addDrink.size.\(option.rawValue)")
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    /// Selected, with its amount, when the volume isn't one of the cards
    /// (an espresso's 30 ml, a spirit's 40 ml).
    private var customCard: some View {
        let isSelected = !DrinkSize.allCases.contains { $0.milliliters == volume }
        return Button {
            showCustom = true
        } label: {
            DrinkCardLabel(symbol: "slider.horizontal.3", isSelected: isSelected) {
                if isSelected {
                    HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xxs) {
                        Text(verbatim: VESSFormat.milliliters(volume))
                            .vessTextStyle(.numberRow)
                            .foregroundStyle(VESSColor.text)
                        Text("ml")
                            .vessTextStyle(.caption)
                            .foregroundStyle(VESSColor.tertiaryText)
                    }
                }
                Text("Custom")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? Text("Custom amount, \(VESSFormat.milliliters(volume)) ml") : Text("Custom amount"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("addDrink.custom")
    }

    /// Today's drinks, newest first.
    @ViewBuilder
    private func todayList(_ logs: [HydrationLog]) -> some View {
        if logs.isEmpty {
            Text(isToday ? "No drinks yet today." : "No drinks that day.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
        } else {
            VESSRowGroup {
                ForEach(logs.sorted { $0.loggedAt > $1.loggedAt }) { log in
                    DrinkLogRow(log: log)
                }
            }
            .vessHairlineBottom()
        }
    }

    /// "Caffeine · 36 of 400 mg ›", to the caffeine screen.
    private func caffeineLink(_ logs: [HydrationLog]) -> some View {
        let total = CaffeineModel.total(logs, on: day, calendar: calendar)
        return Button { showCaffeine = true } label: {
            VESSListRow(
                systemImage: "cup.and.saucer",
                title: Text("Caffeine"),
                value: Text("\(VESSFormat.grams(total)) of \(VESSFormat.grams(CaffeineModel.dailyLimitMilligrams)) mg")
            )
        }
        .buttonStyle(.plain)
        .vessHairlineBottom()
        .accessibilityIdentifier("addDrink.caffeine")
    }

    /// The selected drink's share, which differs per drink (drip coffee 90 %,
    /// flat white 79 %), so it's stated for the drink rather than in general;
    /// then its typical values for this amount.
    private var footnote: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            Text("\(Text(preset.title)) counts at \(Text(contributionPercent / 100, format: .percent.precision(.fractionLength(0)))) toward water. An estimate.")
            DrinkFacts.typicalValues(preset, volume: volume)
        }
        .vessTextStyle(.caption)
        .foregroundStyle(VESSColor.tertiaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var addButton: some View {
        Button(action: add) {
            // A non-breaking space keeps "250 ml" together when it wraps.
            Text("Add \(VESSFormat.milliliters(volume))\u{00A0}ml \(String(localized: preset.title).localizedLowercase)")
        }
        .buttonStyle(.vessPrimary)
        .padding(.horizontal, VESSSpacing.screenInset)
        .padding(.vertical, VESSSpacing.sm)
        .background(VESSColor.card)
        .accessibilityIdentifier("addDrink.submit")
    }

    // MARK: Values

    private var isToday: Bool {
        calendar.isDate(day, inSameDayAs: AppClock.now)
    }

    private func summary(_ logs: [HydrationLog]) -> HydrationProgress? {
        guard let profile = store.profile else { return nil }
        return HydrationProgress(logs: logs, targetMilliliters: profile.waterTargetMilliliters, day: day, calendar: calendar)
    }

    private var contributionPercent: Double {
        DrinkFacts.contributionPercent(preset, profile: store.profile)
    }

    // MARK: Actions

    private func add() {
        guard let profile = store.profile else { return }
        let drink = preset.drink(name: String(localized: preset.title), hydrationContributionPercent: contributionPercent)
        let log = drink.log(userID: profile.id, volumeMilliliters: volume, at: time)
        do {
            try store.add(log)
            undo.show(Text("Added \(VESSFormat.milliliters(volume)) ml of \(drink.name)")) { store in
                try store.deleteHydrationLog(id: log.id)
            }
            dismiss()
        } catch {
            showError = true
        }
    }
}

// MARK: - Sizes

/// The quick sizes on the sheet (reference 10).
enum DrinkSize: String, CaseIterable {
    case glass, mug, can, bottle

    var milliliters: Double {
        switch self {
        case .glass: 150
        case .mug: 250
        case .can: 330
        case .bottle: 500
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .glass: "Glass"
        case .mug: "Mug"
        case .can: "Can"
        case .bottle: "Bottle"
        }
    }

    /// Outline SF Symbols; there is no symbol for a tumbler or a can.
    var symbol: String {
        switch self {
        case .glass: "drop"
        case .mug: "mug"
        case .can: "cylinder"
        case .bottle: "waterbottle"
        }
    }
}

/// A size card: an outline icon over its text. Selected is tinted water.
private struct DrinkCardLabel<Content: View>: View {
    let symbol: String
    let isSelected: Bool
    @ViewBuilder let content: Content

    /// One height for every symbol, so the text lines up across cards.
    @ScaledMetric(relativeTo: .title3) private var iconHeight: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous)
        VStack(spacing: VESSSpacing.xs) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isSelected ? VESSColor.water : VESSColor.secondaryText)
                .frame(height: iconHeight)
                .accessibilityHidden(true)
            content
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, VESSSpacing.md)
        .padding(.horizontal, VESSSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: VESSHitTarget.minimum)
        .background(isSelected ? VESSColor.tintWater : VESSColor.fill, in: shape)
        .overlay(shape.strokeBorder(isSelected ? VESSColor.strokeWater : VESSColor.divider, lineWidth: 1))
        .contentShape(shape)
    }
}

// MARK: - Shared pieces (sheet and Custom amount)

/// Category chips (Water, Tea, Coffee, Other); when the category holds more
/// than one drink, a second row picks the drink.
struct DrinkChoice: View {
    let preset: DrinkPreset
    let onSelect: (DrinkPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            VESSChipFlow {
                ForEach(DrinkCategory.allCases, id: \.self) { category in
                    VESSChip(title: category.title, isSelected: preset.category == category) {
                        guard preset.category != category, let first = category.presets.first else { return }
                        onSelect(first)
                    }
                    .accessibilityIdentifier("addDrink.category.\(category.rawValue)")
                }
            }
            let options = preset.category.presets
            if options.count > 1 {
                VESSChipFlow {
                    ForEach(options, id: \.self) { option in
                        VESSChip(title: option.title, isSelected: option == preset) { onSelect(option) }
                    }
                }
            }
        }
    }
}

/// What VESS says about a drink: its share toward water and its typical values.
enum DrinkFacts {
    /// The user's own share, or the drink's default. Alcohol always counts 0 %.
    static func contributionPercent(_ preset: DrinkPreset, profile: UserProfile?) -> Double {
        guard preset.type != .alcohol else { return 0 }
        return profile?.hydrationContributionPercent(for: preset) ?? preset.defaultHydrationContributionPercent
    }

    /// "Typical values: about 110 kcal and 130 mg caffeine." For alcohol:
    /// "Typical values: 13 g alcohol (1.3 drinks), about 142 kcal."
    /// `nil` for drinks with neither (water).
    static func typicalValues(_ preset: DrinkPreset, volume: Double) -> Text? {
        let drink = preset.drink(name: "")
        let factor = volume / 100
        let kcal = drink.caloriesPer100Milliliters * factor
        let caffeine = drink.caffeineMilligramsPer100Milliliters * factor
        let alcohol = drink.alcoholGramsPer100Milliliters * factor
        if alcohol > 0 {
            return Text("Typical values: \(VESSFormat.grams(alcohol)) g alcohol (\(drinksText(StandardDrink.count(alcoholGrams: alcohol)))), about \(VESSFormat.calories(kcal)) kcal.")
        }
        switch (kcal >= 1, caffeine >= 1) {
        case (true, true): return Text("Typical values: about \(VESSFormat.calories(kcal)) kcal and \(VESSFormat.grams(caffeine)) mg caffeine.")
        case (true, false): return Text("Typical values: about \(VESSFormat.calories(kcal)) kcal.")
        case (false, true): return Text("Typical values: \(VESSFormat.grams(caffeine)) mg caffeine.")
        case (false, false): return nil
        }
    }

    /// "1 drink", "1.3 drinks" (10 g of alcohol each).
    static func drinksText(_ count: Double) -> Text {
        let number = VESSFormat.quantity(count)
        return number == VESSFormat.quantity(1) ? Text("1 drink") : Text("\(number) drinks")
    }
}

/// When a drink was drunk: now for today, noon for an earlier day.
enum DrinkTime {
    static func defaultTime(on day: Date, calendar: Calendar) -> Date {
        if calendar.isDate(day, inSameDayAs: AppClock.now) { return AppClock.now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    /// The chosen day, up to now when it's today.
    static func range(on day: Date, calendar: Calendar) -> ClosedRange<Date> {
        let start = calendar.startOfDay(for: day)
        let isToday = calendar.isDate(day, inSameDayAs: AppClock.now)
        let end = isToday ? AppClock.now : (calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-60) ?? day)
        return start...max(start, end)
    }
}

/// "Time · Now · 18:40 ›" (G01); opens a wheel to change it.
struct DrinkTimeRow: View {
    @Binding var time: Date
    @Binding var isExpanded: Bool
    let range: ClosedRange<Date>
    var identifier = "addDrink.time"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { isExpanded.toggle() }
            } label: {
                HStack(spacing: VESSSpacing.xs) {
                    Text("Time")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                    Spacer(minLength: VESSSpacing.sm)
                    Group {
                        if abs(time.timeIntervalSince(AppClock.now)) < 60 {
                            Text("Now · \(time, format: .dateTime.hour().minute())")
                        } else {
                            Text(time, format: .dateTime.hour().minute())
                        }
                    }
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VESSColor.tertiaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: VESSSize.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the time picker" : "Shows the time picker")
            .accessibilityIdentifier(identifier)
            if isExpanded {
                DatePicker("Time", selection: $time, in: range, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }
        }
        .vessHairlineBottom()
    }
}

/// One drink: time, icon, name, and its volume with "counts N" when only a
/// share counts toward water.
struct DrinkLogRow: View {
    enum Value { case volume, caffeine }

    let log: HydrationLog
    /// What the right-hand side shows: the volume (and share), or caffeine.
    var value: Value = .volume

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    name
                    Text("\(log.loggedAt, format: .dateTime.hour().minute()) · \(amount)")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: VESSSpacing.md) {
                    // As wide as the widest time, so names line up.
                    ZStack(alignment: .leading) {
                        Text(Self.widestTime, format: .dateTime.hour().minute()).hidden()
                        Text(log.loggedAt, format: .dateTime.hour().minute())
                            .foregroundStyle(VESSColor.tertiaryText)
                    }
                    .vessTextStyle(.caption)
                    .monospacedDigit()
                    // The screen's one data hue: water here, caffeine on Caffeine.
                    Image(systemName: log.drinkType.symbol)
                        .foregroundStyle(value == .caffeine ? VESSColor.carbs : VESSColor.water)
                        .frame(width: VESSSize.rowIcon)
                    name
                    Spacer(minLength: VESSSpacing.sm)
                    Text(amount)
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .layoutPriority(1)
                }
            }
        }
        .padding(.vertical, VESSSpacing.sm)
        .frame(minHeight: VESSSize.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(log.loggedAt, format: .dateTime.hour().minute()), \(log.drinkName), \(amount)"))
    }

    private var name: some View {
        Text(verbatim: log.drinkName)
            .vessTextStyle(.bodyM)
            .foregroundStyle(VESSColor.text)
    }

    /// "500 ml", "300 ml · counts 270" for a partial share, or
    /// "330 ml · 1.3 drinks" for alcohol.
    private var amount: String {
        let volume = VESSFormat.milliliters(log.volumeMilliliters)
        if value == .caffeine {
            return String(localized: "\(volume) ml · \(VESSFormat.grams(log.caffeineMilligrams)) mg")
        }
        if log.isAlcoholic, let drinks = log.standardDrinks {
            let number = VESSFormat.quantity(drinks)
            return number == VESSFormat.quantity(1)
                ? String(localized: "\(volume) ml · 1 drink")
                : String(localized: "\(volume) ml · \(number) drinks")
        }
        guard log.hydrationContributionPercent < 100 else { return String(localized: "\(volume) ml") }
        return String(localized: "\(volume) ml · counts \(VESSFormat.milliliters(log.hydrationMilliliters))")
    }

    private static let widestTime: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 58, second: 0, of: Date(timeIntervalSinceReferenceDate: 0)) ?? .now
    }()
}

/// TODAY: one dot per drink from 06 to 24 (larger for big drinks), and a
/// line at now. Decorative for VoiceOver beyond its summary.
struct HydrationTimeline: View {
    let logs: [HydrationLog]
    /// `nil` for a past day.
    let now: Date?
    let calendar: Calendar

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 36

    private static let startHour = 6
    private static let spanMinutes = Double((24 - startHour) * 60)
    /// Dot diameters: a drink of 400 ml or more is drawn larger.
    private static let smallDot: CGFloat = 9
    private static let largeDot: CGFloat = 13

    var body: some View {
        VStack(spacing: VESSSpacing.xs) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let middle = proxy.size.height / 2
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(VESSColor.chartTrack)
                        .frame(width: width, height: 1)
                        .position(x: width / 2, y: middle)
                    ForEach(logs) { log in
                        let diameter = log.volumeMilliliters >= 400 ? Self.largeDot : Self.smallDot
                        Circle()
                            .fill(VESSColor.water)
                            .frame(width: diameter, height: diameter)
                            .position(x: x(for: log.loggedAt, width: width, inset: diameter / 2), y: middle)
                    }
                    if let now {
                        Rectangle()
                            .fill(VESSColor.secondaryText)
                            .frame(width: 1, height: proxy.size.height)
                            .position(x: x(for: now, width: width, inset: 0.5), y: middle)
                    }
                }
            }
            .frame(height: height)
            HStack {
                ForEach([6, 12, 18, 24], id: \.self) { hour in
                    Text(verbatim: String(format: "%02d", hour))
                    if hour != 24 { Spacer(minLength: 0) }
                }
            }
            .vessTextStyle(.caption)
            .foregroundStyle(VESSColor.tertiaryText)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drinks through the day")
        .accessibilityValue(summary)
    }

    private func x(for date: Date, width: CGFloat, inset: CGFloat) -> CGFloat {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double(((parts.hour ?? 0) - Self.startHour) * 60 + (parts.minute ?? 0))
        let fraction = min(max(minutes / Self.spanMinutes, 0), 1)
        return min(max(CGFloat(fraction) * width, inset), width - inset)
    }

    private var summary: Text {
        guard let last = logs.map(\.loggedAt).max() else { return Text("No drinks yet") }
        return Text("^[\(logs.count) drink](inflect: true), last at \(last, format: .dateTime.hour().minute())")
    }
}

#Preview("Add a drink") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddDrinkSheet(day: AppClock.now)
                .previewEnvironment(LocalStore.preview())
        }
        .preferredColorScheme(.dark)
}
