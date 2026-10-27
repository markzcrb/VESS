import SwiftUI

/// 19, 20: log a drink. The drink (icon chips, Custom… for any other),
/// the amount (sizes and a stepper, with what counts toward water and the
/// caffeine), when, Add, and the day's drinks folded away below. The
/// volume drunk and the share counted toward water are kept apart.
///
/// Nothing is wider than the sheet: every row is laid out in the sheet's
/// width (the size cards share it equally; the old cards each insisted on
/// their natural width, so five of them pushed the whole sheet past both
/// edges on device), and only the chip and tab rows scroll, bleeding off
/// the right edge.
struct AddDrinkSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.vessHaptics) private var haptics
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let day: Date
    /// Inside the Add sheet (21): its stack, X and title, so no own header close.
    var embedded = false
    @State private var preset: DrinkPreset = .water
    /// The amount to add: one of the drink's sizes, or a custom amount.
    @State private var volume: Double = DrinkPreset.water.selectedServing.milliliters
    /// % by volume, for alcohol (the Strength row).
    @State private var strength: Double = 0
    @State private var time = AppClock.now
    @State private var showStrength = false
    @State private var showCustom = false
    @State private var showCaffeine = false
    @State private var editing: HydrationLog?
    @State private var showError = false
    @State private var hasLoaded = false
    /// The day's drinks, folded away until asked for.
    @State private var showToday = false
    /// The drink used last, and the size used last for each drink.
    @AppStorage("drink.lastPreset") private var lastPreset = DrinkPreset.water.rawValue
    @AppStorage("drink.lastSizes") private var lastSizes = ""

    private let calendar = Calendar.current

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .background(VESSColor.card)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(VESSRadius.sheet)
        }
    }

    private var content: some View {
        let logs = store.hydrationLogs(on: day, calendar: calendar)

        return ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                if !embedded {
                    HStack {
                        Text("Add a drink")
                            .vessTextStyle(.labelCaps)
                            .foregroundStyle(VESSColor.secondaryText)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                    }
                }
                // 1. What, 2. how much, 3. when, 4. Add; the day's drinks last.
                DrinkTypeChips(selection: preset, onSelect: select, onCustom: { showCustom = true })
                amount
                DrinkCompactTimeRow(time: $time, range: DrinkTime.range(on: day, calendar: calendar))
                addButton
                todaySection(logs)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
            .padding(.bottom, VESSSpacing.xl)
        }
        .vessFoodUndoToast()
        .navigationDestination(isPresented: $showCaffeine) {
            CaffeineView(day: day)
        }
        .navigationDestination(isPresented: $showCustom) {
            CustomDrinkView(day: day, preset: preset, volume: volume, time: time, onClose: { dismiss() })
        }
        .sheet(item: $editing) { log in
            EditDrinkSheet(log: log, day: day)
        }
        .vessErrorAlert(isPresented: $showError, retry: add)
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            time = DrinkTime.defaultTime(on: day, calendar: calendar)
            // The drink and size used last.
            if let last = DrinkPreset(rawValue: lastPreset), DrinkFacts.sheetPresets.contains(last) {
                preset = last
            }
            volume = DrinkFacts.rememberedSize(for: preset, in: lastSizes)
            strength = preset.defaultPercentByVolume ?? 0
        }
    }

    // MARK: Sections

    /// Size chips for the drink, a stepper, and live what counts.
    private var amount: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSSectionHeader(title: "Amount")
            VESSChipFlow(spacing: VESSSpacing.xs) {
                ForEach(DrinkFacts.sizes(for: preset), id: \.self) { size in
                    VESSChip(title: "\(VESSFormat.milliliters(size)) ml", isSelected: volume == size) { setVolume(size) }
                        .accessibilityIdentifier("addDrink.size.\(Int(size))")
                }
            }
            HStack(spacing: VESSSpacing.md) {
                let step = DrinkFacts.step(for: preset)
                VESSIconButton(systemImage: "minus", label: "Less") { setVolume(max(step, volume - step)) }
                    .disabled(volume <= step)
                VStack(spacing: 2) {
                    Text("\(VESSFormat.milliliters(volume)) ml")
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                        .contentTransition(.numericText())
                    Text(countsLine)
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                VESSIconButton(systemImage: "plus", label: "More") { setVolume(min(CustomDrinkView.volumeRange.upperBound, volume + step)) }
            }
            .vessHaptic(.selection, trigger: volume)
        }
    }

    /// "counts as 24 ml water · 63 mg caffeine", live.
    private var countsLine: String {
        let water = VESSFormat.milliliters(volume * contributionPercent / 100)
        let counts = String(localized: "counts as \(water) ml water")
        guard caffeine >= 1 else { return counts }
        return counts + " · " + String(localized: "\(VESSFormat.grams(caffeine)) mg caffeine")
    }

    /// "Today · 7 drinks · 1,03 L of water · 120 mg caffeine": collapsed,
    /// opening the timeline and the list (tap to edit, swipe to delete).
    @ViewBuilder
    private func todaySection(_ logs: [HydrationLog]) -> some View {
        let water = logs.reduce(0) { $0 + $1.hydrationMilliliters }
        let caffeineToday = CaffeineModel.total(logs, on: day, calendar: calendar)
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            Button {
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { showToday.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text(todayTitle(count: logs.count, water: water, caffeine: caffeineToday))
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: VESSSpacing.sm)
                    Image(systemName: showToday ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(VESSColor.tertiaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .vessHairlineBottom()
            .disabled(logs.isEmpty)
            .accessibilityHint(showToday ? "Hides the day's drinks" : "Shows the day's drinks")
            .accessibilityIdentifier("addDrink.today")

            if showToday, !logs.isEmpty {
                HydrationTimeline(logs: logs, now: isToday ? AppClock.now : nil, calendar: calendar)
                VESSRowGroup {
                    ForEach(logs.sorted { $0.loggedAt > $1.loggedAt }) { log in
                        VESSSwipeToDelete(background: VESSColor.card, onTap: { editing = log }, onDelete: { delete(log) }) {
                            DrinkLogRow(log: log)
                        }
                        .accessibilityHint("Edit, or delete")
                        .transition(.opacity)
                    }
                }
                .vessHairlineBottom()
                if caffeineToday >= 1 {
                    Button("Caffeine today") { showCaffeine = true }
                        .buttonStyle(.vessQuiet)
                }
            }
        }
    }

    private func todayTitle(count: Int, water: Double, caffeine: Double) -> String {
        let start = isToday ? String(localized: "Today") : String(localized: "That day")
        guard count > 0 else { return start + " · " + String(localized: "no drinks yet") }
        var parts = [start, String(localized: "^[\(count) drink](inflect: true)"),
                     String(localized: "\(VESSFormat.liters(fromMilliliters: water)) L of water")]
        if caffeine >= 1 { parts.append(String(localized: "\(VESSFormat.grams(caffeine)) mg caffeine")) }
        return parts.joined(separator: " · ")
    }

    /// "Add espresso · 30 ml".
    private var addButton: some View {
        Button(action: add) {
            Text("Add \(String(localized: preset.title).localizedLowercase) · \(VESSFormat.milliliters(volume))\u{00A0}ml")
        }
        .buttonStyle(.vessPrimary)
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

    private var currentDrink: Drink {
        preset.drink(
            name: String(localized: preset.title),
            hydrationContributionPercent: contributionPercent,
            percentByVolume: preset.defaultPercentByVolume == nil ? nil : strength
        )
    }

    /// Caffeine in the chosen amount, mg.
    private var caffeine: Double {
        currentDrink.caffeineMilligramsPer100Milliliters * volume / 100
    }

    // MARK: Actions

    private func select(_ option: DrinkPreset) {
        preset = option
        volume = DrinkFacts.rememberedSize(for: option, in: lastSizes)
        strength = option.defaultPercentByVolume ?? 0
        showStrength = false
    }

    private func setVolume(_ value: Double) {
        withAnimation(reduceMotion ? nil : VESSMotion.selection) { volume = value }
    }

    private func add() {
        guard let profile = store.profile else { return }
        let drink = currentDrink
        let log = drink.log(userID: profile.id, volumeMilliliters: volume, at: time)
        do {
            try store.add(log)
            lastPreset = preset.rawValue
            lastSizes = DrinkFacts.remembering(volume, for: preset, in: lastSizes)
            undo.show(Text("Added \(VESSFormat.milliliters(volume)) ml of \(drink.name.localizedLowercase)")) { store in
                try store.deleteHydrationLog(id: log.id)
                haptics.play(.warning)
            }
            dismiss()
        } catch {
            showError = true
        }
    }

    private func delete(_ log: HydrationLog) {
        do {
            try store.deleteHydrationLog(id: log.id)
            undo.show(Text("Deleted \(log.drinkName)")) { store in
                try store.add(log)
            }
        } catch {
            showError = true
        }
    }
}

/// The drink row: Water, Sparkling, Espresso, Coffee, Tea, Milk, Juice,
/// Smoothie as icon chips, then Custom… for any other drink (alcohol
/// included). Scrolls off the right edge.
struct DrinkTypeChips: View {
    let selection: DrinkPreset
    let onSelect: (DrinkPreset) -> Void
    let onCustom: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            VESSBleedingRow {
                HStack(spacing: VESSSpacing.xs) {
                    ForEach(DrinkFacts.sheetPresets, id: \.self) { option in
                        let isSelected = option == selection
                        Button { onSelect(option) } label: {
                            Label {
                                Text(DrinkFacts.chipTitle(option))
                            } icon: {
                                Image(systemName: option.symbol)
                                    .foregroundStyle(isSelected ? VESSColor.water : VESSColor.secondaryText)
                            }
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                            .padding(.horizontal, VESSSpacing.sm + 2)
                            .frame(minHeight: VESSHitTarget.minimum)
                            .background(isSelected ? VESSColor.tintWater : VESSColor.fill, in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? VESSColor.strokeWater : VESSColor.divider))
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("addDrink.type.\(option.rawValue)")
                        .id(option)
                    }
                    Button(action: onCustom) {
                        Label("Custom…", systemImage: "slider.horizontal.3")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .padding(.horizontal, VESSSpacing.sm + 2)
                            .frame(minHeight: VESSHitTarget.minimum)
                            .background(VESSColor.fill, in: Capsule())
                            .overlay(Capsule().strokeBorder(VESSColor.divider))
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addDrink.custom")
                }
            }
            .vessHaptic(.selection, trigger: selection)
            .onAppear { proxy.scrollTo(selection) }
        }
    }
}

// MARK: - Shared pieces (sheet and Custom amount)

/// The category chips (Water, Tea, Coffee, Other, Alcohol) in one row from
/// the margin, scrolling at larger text sizes; under them the category's
/// drinks as text tabs with a water underline, scrolling off the right
/// edge. The tabs are hidden for a category with one drink.
struct DrinkChoice: View {
    let preset: DrinkPreset
    let onSelect: (DrinkPreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            ScrollViewReader { proxy in
                VESSBleedingRow {
                    HStack(spacing: VESSSpacing.xs) {
                        ForEach(DrinkCategory.allCases, id: \.self) { category in
                            VESSChip(title: category.title, isSelected: preset.category == category) {
                                guard preset.category != category, let first = category.presets.first else { return }
                                onSelect(first)
                            }
                            .accessibilityIdentifier("addDrink.category.\(category.rawValue)")
                            .id(category)
                        }
                    }
                }
                // A chip partly off screen (Alcohol on the SE) comes into view.
                .onChange(of: preset.category) { _, category in proxy.scrollTo(category) }
            }
            let options = preset.category.presets
            if options.count > 1 {
                DrinkTabs(options: options, selection: preset, onSelect: onSelect)
            }
        }
    }
}

/// Text tabs with a water-coloured underline under the selected drink.
private struct DrinkTabs: View {
    let options: [DrinkPreset]
    let selection: DrinkPreset
    let onSelect: (DrinkPreset) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            VESSBleedingRow {
                HStack(spacing: VESSSpacing.xl) {
                    ForEach(options, id: \.self) { option in
                        let isSelected = option == selection
                        Button { onSelect(option) } label: {
                            VStack(spacing: VESSSpacing.xs) {
                                Text(option.tabTitle)
                                    .vessTextStyle(isSelected ? .bodyMStrong : .bodyM)
                                    .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                                    .fixedSize()
                                Rectangle()
                                    .fill(isSelected ? VESSColor.water : Color.clear)
                                    .frame(height: 2)
                            }
                            .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .bottom)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityIdentifier("addDrink.drink.\(option.rawValue)")
                        .id(option)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                VESSHairline().padding(.trailing, -VESSSpacing.screenInset)
            }
            .vessHaptic(.selection, trigger: selection)
            .onAppear { proxy.scrollTo(selection) }
            .onChange(of: selection) { _, new in proxy.scrollTo(new) }
        }
    }
}

/// "Time · Now · 20:22" with a compact time picker (19).
private struct DrinkCompactTimeRow: View {
    @Binding var time: Date
    let range: ClosedRange<Date>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the picker goes under the label, so
        // "Time" and "Now" never break mid-word.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xs))
            : AnyLayout(HStackLayout(spacing: VESSSpacing.xs))
        layout {
            Text("Time")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
                .fixedSize()
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: VESSSpacing.sm)
            }
            HStack(spacing: VESSSpacing.xs) {
                if abs(time.timeIntervalSince(AppClock.now)) < 60 {
                    Text("Now")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize()
                }
                DatePicker("Time", selection: $time, in: range, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(VESSColor.text)
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? VESSSpacing.sm : 0)
        .frame(minHeight: VESSSize.rowHeight)
        .vessHairlineBottom()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("addDrink.time")
    }
}

/// What VESS says about a drink: its share toward water and its typical values.
enum DrinkFacts {
    /// The drinks offered as chips, in order; the rest are under Custom….
    static let sheetPresets: [DrinkPreset] = [.water, .sparklingWater, .espresso, .blackCoffee, .tea, .milk, .juice, .smoothie]

    static func chipTitle(_ preset: DrinkPreset) -> LocalizedStringResource {
        switch preset {
        case .sparklingWater: "Sparkling"
        case .blackCoffee: "Coffee"
        default: preset.title
        }
    }

    /// The size chips: Espresso 30/60, Coffee 150/250/350, Water
    /// 250/330/500/750; otherwise the drink's three sizes.
    static func sizes(for preset: DrinkPreset) -> [Double] {
        switch preset {
        case .espresso: [30, 60]
        case .blackCoffee: [150, 250, 350]
        case .water, .sparklingWater: [250, 330, 500, 750]
        default: preset.servings.map(\.milliliters)
        }
    }

    /// The stepper's step: 10 ml for espresso, else 50 ml.
    static func step(for preset: DrinkPreset) -> Double {
        preset == .espresso ? 10 : 50
    }

    /// The size used last for this drink, else its middle size.
    static func rememberedSize(for preset: DrinkPreset, in stored: String) -> Double {
        if let sizes = try? JSONDecoder().decode([String: Double].self, from: Data(stored.utf8)), let size = sizes[preset.rawValue], size > 0 {
            return size
        }
        let sizes = sizes(for: preset)
        let usual = preset.selectedServing.milliliters
        return sizes.contains(usual) ? usual : sizes.first ?? usual
    }

    static func remembering(_ size: Double, for preset: DrinkPreset, in stored: String) -> String {
        var sizes = (try? JSONDecoder().decode([String: Double].self, from: Data(stored.utf8))) ?? [:]
        sizes[preset.rawValue] = size
        return (try? JSONEncoder().encode(sizes)).flatMap { String(data: $0, encoding: .utf8) } ?? stored
    }

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
        // Drink kcal count in the day's energy and in Fuel (alcohol: energy only).
        case (true, true): return Text("Typical values: about \(VESSFormat.calories(kcal)) kcal and \(VESSFormat.grams(caffeine)) mg caffeine. The kcal count in your energy.")
        case (true, false): return Text("Typical values: about \(VESSFormat.calories(kcal)) kcal, counted in your energy.")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the time goes under the label, so "Time"
        // and "Now" never break mid-word (same as the drink sheet's row).
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xxs))
            : AnyLayout(HStackLayout(spacing: VESSSpacing.xs))
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { isExpanded.toggle() }
            } label: {
                layout {
                    Text("Time")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize()
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: VESSSpacing.sm)
                    }
                    Group {
                        if abs(time.timeIntervalSince(AppClock.now)) < 60 {
                            Text("Now · \(time, format: .dateTime.hour().minute())")
                        } else {
                            Text(time, format: .dateTime.hour().minute())
                        }
                    }
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(VESSColor.tertiaryText)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: VESSSize.rowHeight, alignment: .leading)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? VESSSpacing.sm : 0)
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

/// One drink: time, icon, name, and its volume with "counts as N ml" when only a
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
                    .fixedSize()
                    // The screen's one data hue: water here, caffeine on Caffeine.
                    Image(systemName: log.drinkType.symbol)
                        .foregroundStyle(value == .caffeine ? VESSColor.carbs : VESSColor.water)
                        .frame(width: VESSSize.rowIcon)
                    // The name takes the flexible width; the amount keeps its
                    // natural width beside it, or moves under the name when
                    // both don't fit, so no word is ever broken.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: VESSSpacing.sm) {
                            name.fixedSize()
                            Spacer(minLength: VESSSpacing.sm)
                            amountText.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                            name.fixedSize(horizontal: false, vertical: true)
                            amountText.fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
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

    private var amountText: some View {
        Text(amount)
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
    }

    /// "500 ml", "300 ml · counts as 270 ml" for a partial share, or
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
        return String(localized: "\(volume) ml · counts as \(VESSFormat.milliliters(log.hydrationMilliliters)) ml")
    }

    private static let widestTime: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 58, second: 0, of: Date(timeIntervalSinceReferenceDate: 0)) ?? .now
    }()
}

/// TODAY: one dot per drink from 06 to 24 (larger for big drinks), and a
/// line at now. From 00 when any drink (or now) is before 06, so nothing is
/// drawn away from its real time. Decorative for VoiceOver beyond its summary.
struct HydrationTimeline: View {
    let logs: [HydrationLog]
    /// `nil` for a past day.
    let now: Date?
    let calendar: Calendar

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 36

    /// 06, or 00 when a drink or now is earlier than 06.
    static func startHour(logs: [HydrationLog], now: Date?, calendar: Calendar) -> Int {
        let times = logs.map(\.loggedAt) + (now.map { [$0] } ?? [])
        return times.contains { calendar.component(.hour, from: $0) < 6 } ? 0 : 6
    }
    /// Dot diameters: a drink of 400 ml or more is drawn larger.
    private static let smallDot: CGFloat = 9
    private static let largeDot: CGFloat = 13

    var body: some View {
        let start = Self.startHour(logs: logs, now: now, calendar: calendar)
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
                            .position(x: x(for: log.loggedAt, start: start, width: width, inset: diameter / 2), y: middle)
                    }
                    if let now {
                        Rectangle()
                            .fill(VESSColor.secondaryText)
                            .frame(width: 1, height: proxy.size.height)
                            .position(x: x(for: now, start: start, width: width, inset: 0.5), y: middle)
                    }
                }
            }
            .frame(height: height)
            HStack {
                ForEach(Array(stride(from: start, through: 24, by: 6)), id: \.self) { hour in
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

    private func x(for date: Date, start: Int, width: CGFloat, inset: CGFloat) -> CGFloat {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double(((parts.hour ?? 0) - start) * 60 + (parts.minute ?? 0))
        let fraction = min(max(minutes / Double((24 - start) * 60), 0), 1)
        return min(max(CGFloat(fraction) * width, inset), width - inset)
    }

    private var summary: Text {
        guard let last = logs.map(\.loggedAt).max() else { return Text("No drinks yet") }
        return Text("^[\(logs.count) drink](inflect: true), last at \(last, format: .dateTime.hour().minute())")
    }
}

#if DEBUG
#Preview("Add a drink") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddDrinkSheet(day: AppClock.now)
                .previewEnvironment(LocalStore.preview())
        }
        .preferredColorScheme(.dark)
}
#endif
