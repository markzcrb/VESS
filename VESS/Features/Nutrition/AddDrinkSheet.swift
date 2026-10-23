import SwiftUI

/// 19, 20: log a drink. The day's hydration, a category and its drinks,
/// three sizes and Custom, when, caffeine or strength, today's drinks, and
/// Add. The volume drunk and the share counted toward water are kept apart.
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

    private let calendar = Calendar.current

    var body: some View {
        let logs = store.hydrationLogs(on: day, calendar: calendar)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    header(logs: logs)
                    DrinkChoice(preset: preset, onSelect: select)
                    sizeCards
                    VStack(spacing: 0) {
                        DrinkCompactTimeRow(time: $time, range: DrinkTime.range(on: day, calendar: calendar))
                        if caffeine >= 1 { caffeineRow(logs) }
                        if preset.defaultPercentByVolume != nil { strengthRow }
                    }
                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        VESSSectionHeader(title: isToday ? "Today" : "That day")
                        HydrationTimeline(logs: logs, now: isToday ? AppClock.now : nil, calendar: calendar)
                    }
                    todayList(logs)
                    footnote
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.xl)
            }
            .background(VESSColor.card)
            .vessBottomAction { addButton }
            .vessFoodUndoToast()
            .toolbar(.hidden, for: .navigationBar)
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
                strength = preset.defaultPercentByVolume ?? 0
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

    /// The drink's three sizes and Custom, equal widths in one row; two
    /// columns from the xxLarge text size.
    @ViewBuilder
    private var sizeCards: some View {
        let cards = Group {
            ForEach(preset.servings, id: \.self) { sizeCard($0) }
            customCard
        }
        Group {
            if dynamicTypeSize <= .xLarge {
                HStack(alignment: .top, spacing: VESSSpacing.xs) { cards }
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: VESSSpacing.sm), GridItem(.flexible(), spacing: VESSSpacing.sm)], spacing: VESSSpacing.sm) {
                    cards
                }
            }
        }
        .vessHaptic(.selection, trigger: volume)
    }

    private func sizeCard(_ serving: DrinkServing) -> some View {
        let isSelected = serving.milliliters == volume
        return Button {
            volume = serving.milliliters
        } label: {
            DrinkCardLabel(symbol: preset.symbol, isSelected: isSelected) {
                DrinkAmountText(milliliters: serving.milliliters)
                Text(serving.name.title)
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(serving.name.title)), \(VESSFormat.milliliters(serving.milliliters)) ml"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("addDrink.size.\(serving.name.rawValue)")
    }

    /// "Any · Custom"; selected, with its amount, when the volume isn't one
    /// of the sizes.
    private var customCard: some View {
        let isSelected = !preset.servings.contains { $0.milliliters == volume }
        return Button {
            showCustom = true
        } label: {
            DrinkCardLabel(symbol: "slider.horizontal.3", isSelected: isSelected) {
                if isSelected {
                    DrinkAmountText(milliliters: volume)
                } else {
                    Text("Any")
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                }
                Text("Custom")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isSelected ? Text("Custom amount, \(VESSFormat.milliliters(volume)) ml") : Text("Custom amount"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("addDrink.custom")
    }

    /// "Caffeine · ≈ 130 mg in this latte · 196 / 400 mg ›".
    private func caffeineRow(_ logs: [HydrationLog]) -> some View {
        let total = CaffeineModel.total(logs, on: day, calendar: calendar)
        return Button { showCaffeine = true } label: {
            VESSListRow(
                title: Text("Caffeine"),
                subtitle: Text("≈ \(VESSFormat.grams(caffeine)) mg in this \(String(localized: preset.title).localizedLowercase)"),
                value: Text("\(VESSFormat.grams(total)) / \(VESSFormat.grams(CaffeineModel.dailyLimitMilligrams)) mg")
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vessHairlineBottom()
        .accessibilityIdentifier("addDrink.caffeine")
    }

    /// "Strength · 12.5 % ABV ›"; opens a stepper in steps of 0.5 %.
    private var strengthRow: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { showStrength.toggle() }
            } label: {
                VESSListRow(title: Text("Strength"), value: Text("\(Self.percent(strength)) ABV"))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showStrength ? "Hides the strength" : "Changes the strength")
            .accessibilityIdentifier("addDrink.strength")
            if showStrength {
                HStack(spacing: VESSSpacing.md) {
                    VESSIconButton(systemImage: "minus", label: "Weaker") { strength = max(Self.strengthRange.lowerBound, strength - 0.5) }
                        .disabled(strength <= Self.strengthRange.lowerBound)
                    Text(verbatim: Self.percent(strength))
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                    VESSIconButton(systemImage: "plus", label: "Stronger") { strength = min(Self.strengthRange.upperBound, strength + 0.5) }
                        .disabled(strength >= Self.strengthRange.upperBound)
                }
                .padding(.vertical, VESSSpacing.sm)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Strength")
                .accessibilityValue(Text(verbatim: "\(Self.percent(strength)) ABV"))
                .vessHaptic(.selection, trigger: strength)
            }
        }
        .vessHairlineBottom()
    }

    private static let strengthRange = 0.5...80.0

    /// "12.5 %", "5 %".
    private static func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1))))\u{00A0}%"
    }

    /// Today's drinks, newest first. Tap to edit; swipe to delete (Undo).
    @ViewBuilder
    private func todayList(_ logs: [HydrationLog]) -> some View {
        if logs.isEmpty {
            Text(isToday ? "No drinks yet today." : "No drinks that day.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
        } else {
            VESSRowGroup {
                ForEach(logs.sorted { $0.loggedAt > $1.loggedAt }) { log in
                    VESSSwipeToDelete(background: VESSColor.card, onTap: { editing = log }, onDelete: { delete(log) }) {
                        DrinkLogRow(log: log)
                    }
                    .accessibilityHint("Edit, or delete")
                }
            }
            .vessHairlineBottom()
        }
    }

    /// Water share and typical values; for alcohol, its kcal and where they count.
    private var footnote: some View {
        let drink = currentDrink
        let factor = volume / 100
        return Group {
            if preset.defaultPercentByVolume != nil {
                let grams = drink.alcoholGramsPer100Milliliters * factor
                Text("About \(VESSFormat.calories(drink.caloriesPer100Milliliters * factor)) kcal and \(VESSFormat.grams(grams)) g alcohol (\(DrinkFacts.drinksText(StandardDrink.count(alcoholGrams: grams)))), typical values. Counted in your energy, not in Fuel. Alcohol doesn't count toward water.")
            } else {
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text("\(Text(preset.title)) counts at \(Text(contributionPercent / 100, format: .percent.precision(.fractionLength(0)))) toward water. An estimate.")
                    DrinkFacts.typicalValues(preset, volume: volume)
                }
            }
        }
        .vessTextStyle(.caption)
        .foregroundStyle(VESSColor.tertiaryText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "Add latte · 350 ml".
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
        volume = option.selectedServing.milliliters
        strength = option.defaultPercentByVolume ?? 0
        showStrength = false
    }

    private func add() {
        guard let profile = store.profile else { return }
        let drink = currentDrink
        let log = drink.log(userID: profile.id, volumeMilliliters: volume, at: time)
        do {
            try store.add(log)
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

/// "350 ml", the number stronger than its unit. Shrinks rather than clips.
private struct DrinkAmountText: View {
    let milliliters: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: VESSFormat.milliliters(milliliters))
                .vessTextStyle(.numberRow)
                .foregroundStyle(VESSColor.text)
            Text("ml")
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
        }
    }
}

/// A size card: an outline icon over its text. Selected is tinted water.
/// Takes its share of the row's width; text shrinks a little before it
/// would clip, and never widens the card.
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
        .minimumScaleFactor(0.7)
        .padding(.vertical, VESSSpacing.md)
        .padding(.horizontal, VESSSpacing.xxs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: VESSHitTarget.minimum)
        .background(isSelected ? VESSColor.tintWater : VESSColor.fill, in: shape)
        .overlay(shape.strokeBorder(isSelected ? VESSColor.strokeWater : VESSColor.divider, lineWidth: 1))
        .contentShape(shape)
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
                BleedingRow {
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

/// A horizontal scroller that starts at the screen margin and runs off the
/// sheet's edges, without making its parent any wider.
private struct BleedingRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // At rest the row starts at the margin; scrolled, it runs off both
        // sheet edges instead of being cut at the margin.
        .contentMargins(.horizontal, VESSSpacing.screenInset, for: .scrollContent)
        .padding(.horizontal, -VESSSpacing.screenInset)
    }
}

/// Text tabs with a water-coloured underline under the selected drink.
private struct DrinkTabs: View {
    let options: [DrinkPreset]
    let selection: DrinkPreset
    let onSelect: (DrinkPreset) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            BleedingRow {
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
