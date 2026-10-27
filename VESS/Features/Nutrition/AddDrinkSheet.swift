import SwiftUI

/// D01, D02: log a drink, laid out like Add › Workout. TYPE (seven tiles
/// and More… for every other drink and the user's own), SIZE (the drink's
/// sizes and Custom with a stepper), CAFFEINE (Regular / Half / Decaf, for
/// coffee and tea), the estimate, when, Add, and a Today row that opens the
/// day's drinks. The volume drunk and the share counted toward water are
/// kept apart.
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
    /// One of the user's saved drinks, when that's what's chosen.
    @State private var saved: SavedDrink?
    @State private var editingSaved: SavedDrink?
    /// The amount to add: one of the drink's sizes, or a custom amount.
    @State private var volume: Double = DrinkPreset.water.selectedServing.milliliters
    @State private var showCustomSize = false
    @State private var strength: CaffeineStrength = .regular
    @State private var time = AppClock.now
    @State private var showTimePicker = false
    @State private var showMore = false
    @State private var showNewDrink = false
    @State private var showToday = false
    @State private var showError = false
    @State private var hasLoaded = false
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
                section("Type") { typeTiles }
                section("Size") { sizes }
                if DrinkFacts.offersStrength(saved == nil ? preset : nil) {
                    section("Caffeine") {
                        VESSSegmented(selection: $strength, options: CaffeineStrength.allCases.map { ($0, $0.title) })
                            .accessibilityIdentifier("addDrink.strength")
                    }
                }
                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    estimateLine(logs)
                    DrinkTimeRow(time: $time, isExpanded: $showTimePicker, range: DrinkTime.range(on: day, calendar: calendar))
                }
                addButton
                todayRow(logs)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
            .padding(.bottom, VESSSpacing.xl)
        }
        .vessFoodUndoToast()
        .navigationDestination(isPresented: $showMore) {
            MoreDrinksView(
                selection: saved == nil ? preset : nil,
                saved: store.profile?.savedDrinks ?? [],
                savedSelection: saved?.id,
                onSelect: { select($0); showMore = false },
                onSelectSaved: { select($0); showMore = false },
                onEditSaved: { editingSaved = $0 },
                onDeleteSaved: deleteSaved,
                onNew: { showNewDrink = true }
            )
        }
        .navigationDestination(isPresented: $showNewDrink) {
            CustomDrinkView(day: day, preset: preset, volume: volume, time: time, onClose: { dismiss() })
        }
        .navigationDestination(item: $editingSaved) { drink in
            CustomDrinkView(editing: drink, day: day, onClose: { dismiss() })
        }
        .navigationDestination(isPresented: $showToday) {
            DrinksDayView(day: day)
        }
        .vessErrorAlert(isPresented: $showError, retry: add)
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            time = DrinkTime.defaultTime(on: day, calendar: calendar)
            // The drink and size used last.
            if let last = DrinkPreset(rawValue: lastPreset) { preset = last }
            volume = DrinkFacts.rememberedSize(for: preset, in: lastSizes)
        }
    }

    // MARK: Sections

    private func section<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: title)
            content()
        }
    }

    /// Seven drinks and More…; More shows the drink chosen from its list.
    private var typeTiles: some View {
        LazyVGrid(columns: VESSPickTile.columns(for: dynamicTypeSize), spacing: VESSSpacing.xs) {
            ForEach(DrinkFacts.sheetPresets, id: \.self) { option in
                VESSPickTile(title: Text(DrinkFacts.chipTitle(option)), systemImage: option.symbol,
                             isSelected: saved == nil && preset == option) { select(option) }
                    .accessibilityIdentifier("addDrink.type.\(option.rawValue)")
            }
            moreTile
        }
    }

    private var moreTile: some View {
        let fromList = saved != nil || !DrinkFacts.sheetPresets.contains(preset)
        let title: Text = if let saved { Text(verbatim: saved.name) } else if fromList { Text(DrinkFacts.chipTitle(preset)) } else { Text("More") }
        return VESSPickTile(title: title, systemImage: fromList ? (saved?.basedOn ?? preset).symbol : "ellipsis",
                            isSelected: fromList) { showMore = true }
            .accessibilityHint("Shows every drink")
            .accessibilityIdentifier("addDrink.more")
    }

    /// The drink's sizes, then Custom (its amount when it isn't a size) with a stepper.
    private var sizes: some View {
        let options = saved.map { [$0.volumeMilliliters] } ?? DrinkFacts.sizes(for: preset)
        let isCustom = showCustomSize || !options.contains(volume)
        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSChipFlow(spacing: VESSSpacing.xs) {
                ForEach(options, id: \.self) { size in
                    VESSChip(title: "\(DrinkFacts.sizeTitle(size, for: saved == nil ? preset : nil))", isSelected: !isCustom && volume == size) {
                        showCustomSize = false
                        setVolume(size)
                    }
                    .accessibilityIdentifier("addDrink.size.\(Int(size))")
                }
                VESSChip(title: options.contains(volume) ? "Custom" : "\(VESSFormat.milliliters(volume))\u{00A0}ml",
                         isSelected: isCustom) {
                    withAnimation(reduceMotion ? nil : VESSMotion.selection) { showCustomSize = true }
                }
                .accessibilityLabel(isCustom ? Text("Custom, \(VESSFormat.milliliters(volume))\u{00A0}ml") : Text("Custom"))
                .accessibilityIdentifier("addDrink.custom")
            }
            if isCustom {
                let step = DrinkFacts.step(for: preset)
                HStack(spacing: VESSSpacing.md) {
                    VESSIconButton(systemImage: "minus", label: "Smaller amount") { setVolume(max(step, volume - step)) }
                        .disabled(volume <= step)
                    Text("\(VESSFormat.milliliters(volume))\u{00A0}ml")
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                        .contentTransition(.numericText())
                        .frame(maxWidth: .infinity)
                    VESSIconButton(systemImage: "plus", label: "Larger amount") { setVolume(min(CustomDrinkView.volumeRange.upperBound, volume + step)) }
                        .disabled(volume >= CustomDrinkView.volumeRange.upperBound)
                }
                .vessHaptic(.selection, trigger: volume)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Amount")
                .accessibilityValue(Text("\(VESSFormat.milliliters(volume))\u{00A0}ml"))
            }
        }
    }

    /// "330 ml · toward water · → 1,9 of 2,5 L with this", or for caffeine
    /// "≈ 64 mg · caffeine · counts as 24 ml water · → 128 of 400 mg with this".
    private func estimateLine(_ logs: [HydrationLog]) -> some View {
        let estimate = DrinkEstimate(
            volume: volume, contributionPercent: contributionPercent, caffeine: caffeine,
            alcoholGrams: currentDrink.alcoholGramsPer100Milliliters * volume / 100,
            waterToday: logs.reduce(0) { $0 + $1.hydrationMilliliters },
            waterTarget: store.profile?.waterTargetMilliliters ?? 0,
            caffeineToday: CaffeineModel.total(logs, on: day, calendar: calendar)
        )
        // The caption wraps beside the number (D02); under it at accessibility sizes.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: VESSSpacing.sm))
        return layout {
            Text(verbatim: estimate.value)
                .vessTextStyle(.displayM)
                .foregroundStyle(VESSColor.text)
                .contentTransition(.numericText())
                .fixedSize()
            Text(verbatim: estimate.context)
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("addDrink.estimate")
    }

    /// "Add espresso · 30 ml".
    private var addButton: some View {
        Button(action: add) {
            Text("Add \(saved?.name ?? String(localized: preset.title).localizedLowercase) · \(VESSFormat.milliliters(volume))\u{00A0}ml")
        }
        .buttonStyle(.vessPrimary)
        .accessibilityIdentifier("addDrink.submit")
    }

    /// "Today · 4 drinks · 1,6 L of water · 64 mg caffeine ›": opens the
    /// timeline and the list.
    private func todayRow(_ logs: [HydrationLog]) -> some View {
        Button { showToday = true } label: {
            VESSListRow(systemImage: "chart.bar",
                        title: isToday ? Text("Today") : Text("That day"),
                        subtitle: Text(verbatim: DrinkFacts.daySummary(logs, on: day, calendar: calendar)))
        }
        .buttonStyle(.plain)
        .vessHairlineBottom()
        .disabled(logs.isEmpty)
        .accessibilityIdentifier("addDrink.today")
    }

    // MARK: Values

    private var isToday: Bool {
        calendar.isDate(day, inSameDayAs: AppClock.now)
    }

    private var contributionPercent: Double {
        saved?.hydrationContributionPercent ?? DrinkFacts.contributionPercent(preset, profile: store.profile)
    }

    private var currentDrink: Drink {
        // A saved drink: its own caffeine per 100 ml, whatever the amount.
        if let saved { return saved.drink() }
        var drink = preset.drink(
            name: String(localized: preset.title),
            hydrationContributionPercent: contributionPercent,
            percentByVolume: preset.defaultPercentByVolume
        )
        if DrinkFacts.offersStrength(preset) {
            drink.caffeineMilligramsPer100Milliliters *= strength.factor
        }
        return drink
    }

    /// Caffeine in the chosen amount, mg.
    private var caffeine: Double {
        currentDrink.caffeineMilligramsPer100Milliliters * volume / 100
    }

    // MARK: Actions

    private func select(_ drink: SavedDrink) {
        saved = drink
        preset = drink.basedOn
        volume = drink.volumeMilliliters
        showCustomSize = false
        strength = .regular
    }

    private func deleteSaved(_ drink: SavedDrink) {
        guard var profile = store.profile else { return }
        profile.savedDrinks = (profile.savedDrinks ?? []).filter { $0.id != drink.id }
        if saved?.id == drink.id { select(.water) }
        do { try store.saveProfile(profile) } catch { showError = true }
    }

    private func select(_ option: DrinkPreset) {
        saved = nil
        preset = option
        volume = DrinkFacts.rememberedSize(for: option, in: lastSizes)
        showCustomSize = false
        strength = .regular
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
            undo.show(Text("Added \(VESSFormat.milliliters(volume))\u{00A0}ml of \(drink.name.localizedLowercase)")) { store in
                try store.deleteHydrationLog(id: log.id)
                haptics.play(.warning)
            }
            dismiss()
        } catch {
            showError = true
        }
    }
}

/// What the estimate line says (D01, D02). Pure, for tests.
struct DrinkEstimate {
    let volume: Double
    let contributionPercent: Double
    let caffeine: Double
    let alcoholGrams: Double
    /// Before this drink.
    let waterToday: Double
    let waterTarget: Double
    /// Before this drink.
    let caffeineToday: Double

    private var counted: Double { volume * contributionPercent / 100 }

    /// "330 ml", or "≈ 64 mg" for a caffeinated drink.
    var value: String {
        caffeine >= 1 ? "≈\u{00A0}\(VESSFormat.grams(caffeine))\u{00A0}mg" : "\(VESSFormat.milliliters(volume))\u{00A0}ml"
    }

    var context: String {
        let water = String(localized: "→\u{00A0}\(VESSFormat.liters(fromMilliliters: waterToday + counted)) of \(VESSFormat.liters(fromMilliliters: waterTarget))\u{00A0}L with this")
        if caffeine >= 1 {
            return [String(localized: "caffeine"),
                    String(localized: "counts as \(VESSFormat.milliliters(counted))\u{00A0}ml water"),
                    String(localized: "→\u{00A0}\(VESSFormat.grams(caffeineToday + caffeine)) of \(VESSFormat.grams(CaffeineModel.dailyLimitMilligrams))\u{00A0}mg with this")]
                .joined(separator: " · ")
        }
        if alcoholGrams > 0 {
            let drinks = VESSFormat.quantity(StandardDrink.count(alcoholGrams: alcoholGrams))
            let count = drinks == VESSFormat.quantity(1) ? String(localized: "1 drink") : String(localized: "\(drinks) drinks")
            return count + " · " + String(localized: "doesn't count toward water")
        }
        let share = contributionPercent >= 100
            ? String(localized: "toward water")
            : String(localized: "counts as \(VESSFormat.milliliters(counted))\u{00A0}ml water")
        return waterTarget > 0 ? share + " · " + water : share
    }
}

/// More… (D01): every other drink, the user's own, and New drink.
private struct MoreDrinksView: View {
    let selection: DrinkPreset?
    let saved: [SavedDrink]
    let savedSelection: UUID?
    let onSelect: (DrinkPreset) -> Void
    let onSelectSaved: (SavedDrink) -> Void
    let onEditSaved: (SavedDrink) -> Void
    let onDeleteSaved: (SavedDrink) -> Void
    let onNew: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                if !saved.isEmpty {
                    group("Your drinks") {
                        ForEach(saved) { drink in
                            Button { onSelectSaved(drink) } label: {
                                row(symbol: drink.basedOn.symbol, title: Text(verbatim: drink.name),
                                    subtitle: Text("\(VESSFormat.milliliters(drink.volumeMilliliters))\u{00A0}ml"),
                                    isSelected: drink.id == savedSelection)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { onEditSaved(drink) }
                                Button("Delete", systemImage: "trash", role: .destructive) { onDeleteSaved(drink) }
                            }
                            .accessibilityAction(named: "Edit") { onEditSaved(drink) }
                            .accessibilityAction(named: "Delete") { onDeleteSaved(drink) }
                            .accessibilityIdentifier("addDrink.saved")
                        }
                    }
                }
                ForEach(DrinkFacts.moreSections, id: \.title.key) { section in
                    group(section.title) {
                        ForEach(section.presets, id: \.self) { option in
                            Button { onSelect(option) } label: {
                                row(symbol: option.symbol, title: Text(option.title), subtitle: nil, isSelected: option == selection)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("addDrink.drink.\(option.rawValue)")
                        }
                    }
                }
                VESSRowGroup {
                    Button(action: onNew) {
                        VESSListRow(systemImage: "plus", title: Text("New drink"), subtitle: Text("Your own amount, caffeine and kcal"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addDrink.new")
                }
                .vessHairlineBottom()
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
            .padding(.bottom, VESSSpacing.huge)
        }
        .background(VESSColor.card)
        .vessDetailTitle("Drinks")
    }

    private func group<Content: View>(_ title: LocalizedStringResource, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            VESSSectionHeader(title: title)
            VESSRowGroup { content() }
                .vessHairlineBottom()
        }
    }

    private func row(symbol: String, title: Text, subtitle: Text?, isSelected: Bool) -> some View {
        VESSListRow(systemImage: symbol, title: title, subtitle: subtitle, showsChevron: false) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VESSColor.text)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Today's drinks (from the Today row): the timeline, the list (tap to
/// edit, swipe to delete) and Caffeine today.
private struct DrinksDayView: View {
    let day: Date

    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @State private var editing: HydrationLog?
    @State private var showCaffeine = false
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        let logs = store.hydrationLogs(on: day, calendar: calendar)
        let isToday = calendar.isDate(day, inSameDayAs: AppClock.now)
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                Text(verbatim: DrinkFacts.daySummary(logs, on: day, calendar: calendar))
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !logs.isEmpty {
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
                    .vessListChanges(logs.map(\.id))
                    .vessHairlineBottom()
                }
                if CaffeineModel.total(logs, on: day, calendar: calendar) >= 1 {
                    Button("Caffeine today") { showCaffeine = true }
                        .buttonStyle(.vessQuiet)
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
            .padding(.bottom, VESSSpacing.huge)
        }
        .background(VESSColor.card)
        .vessDetailTitle(isToday ? "Today's drinks" : "That day's drinks")
        .vessFoodUndoToast()
        .navigationDestination(isPresented: $showCaffeine) { CaffeineView(day: day) }
        .sheet(item: $editing) { log in EditDrinkSheet(log: log, day: day) }
        .vessErrorAlert(isPresented: $showError)
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

/// What VESS says about a drink: its share toward water and its typical values.
enum DrinkFacts {
    /// The drinks offered as tiles, in order; the rest are under More….
    static let sheetPresets: [DrinkPreset] = [.water, .sparklingWater, .blackCoffee, .espresso, .tea, .milk, .juice]

    /// More…: every other drink, by kind.
    static var moreSections: [(title: LocalizedStringResource, presets: [DrinkPreset])] {
        let rest = { (category: DrinkCategory) in category.presets.filter { !sheetPresets.contains($0) } }
        return [("Coffee and tea", rest(.coffee) + rest(.tea)), ("Other", rest(.other)), ("Alcohol", rest(.alcohol))]
    }

    /// Regular / Half / Decaf for coffee and tea with caffeine (not decaf itself).
    static func offersStrength(_ preset: DrinkPreset?) -> Bool {
        guard let preset, preset != .decaf else { return false }
        return (preset.type == .coffee || preset.type == .tea) && preset.caffeineMilligramsPer100Milliliters > 0
    }

    /// "250 ml"; espresso names its shots: "Single · 30 ml".
    static func sizeTitle(_ size: Double, for preset: DrinkPreset?) -> String {
        let amount = "\(VESSFormat.milliliters(size))\u{00A0}ml"
        guard preset == .espresso, let serving = DrinkPreset.espresso.servings.first(where: { $0.milliliters == size }) else { return amount }
        return String(localized: serving.name.title) + " · " + amount
    }

    /// "4 drinks · 1,6 L of water · 64 mg caffeine", or "No drinks yet".
    static func daySummary(_ logs: [HydrationLog], on day: Date, calendar: Calendar) -> String {
        guard !logs.isEmpty else { return String(localized: "No drinks yet") }
        // AttributedString resolves the plural ("1 drink", "4 drinks").
        let drinks = String(AttributedString(localized: "^[\(logs.count) drink](inflect: true)").characters)
        let water = logs.reduce(0) { $0 + $1.hydrationMilliliters }
        var parts = [drinks, String(localized: "\(VESSFormat.liters(fromMilliliters: water))\u{00A0}L of water")]
        let caffeine = CaffeineModel.total(logs, on: day, calendar: calendar)
        if caffeine >= 1 { parts.append(String(localized: "\(VESSFormat.grams(caffeine))\u{00A0}mg caffeine")) }
        return parts.joined(separator: " · ")
    }

    static func chipTitle(_ preset: DrinkPreset) -> LocalizedStringResource {
        switch preset {
        case .sparklingWater: "Sparkling"
        case .blackCoffee: "Coffee"
        case .tea: "Tea"
        default: preset.title
        }
    }

    /// The size chips: Espresso single/double/lungo, Coffee 150/250/350, Water
    /// 250/330/500/750; otherwise the drink's three sizes.
    static func sizes(for preset: DrinkPreset) -> [Double] {
        switch preset {
        case .espresso: DrinkPreset.espresso.servings.map(\.milliliters)
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
        // Espresso starts at a single shot.
        if preset == .espresso { return sizes.first ?? usual }
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
            return Text("Typical values: \(VESSFormat.grams(alcohol))\u{00A0}g alcohol (\(drinksText(StandardDrink.count(alcoholGrams: alcohol)))), about \(VESSFormat.calories(kcal))\u{00A0}kcal.")
        }
        switch (kcal >= 1, caffeine >= 1) {
        // Drink kcal count in the day's energy and in Fuel (alcohol: energy only).
        case (true, true): return Text("Typical values: about \(VESSFormat.calories(kcal))\u{00A0}kcal and \(VESSFormat.grams(caffeine))\u{00A0}mg caffeine. The kcal count in your energy.")
        case (true, false): return Text("Typical values: about \(VESSFormat.calories(kcal))\u{00A0}kcal, counted in your energy.")
        case (false, true): return Text("Typical values: \(VESSFormat.grams(caffeine))\u{00A0}mg caffeine.")
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
            return String(localized: "\(volume)\u{00A0}ml · \(VESSFormat.grams(log.caffeineMilligrams))\u{00A0}mg")
        }
        if log.isAlcoholic, let drinks = log.standardDrinks {
            let number = VESSFormat.quantity(drinks)
            return number == VESSFormat.quantity(1)
                ? String(localized: "\(volume)\u{00A0}ml · 1 drink")
                : String(localized: "\(volume)\u{00A0}ml · \(number) drinks")
        }
        guard log.hydrationContributionPercent < 100 else { return String(localized: "\(volume)\u{00A0}ml") }
        return String(localized: "\(volume)\u{00A0}ml · counts as \(VESSFormat.milliliters(log.hydrationMilliliters))\u{00A0}ml")
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
