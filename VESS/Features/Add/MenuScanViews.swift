import SwiftUI

/// A menu read once: kept while the Add sheet is open, never stored.
struct MenuScanResult: Equatable {
    let title: String?
    let dishes: [MenuDish]
    let note: String?
}

/// What's left today, for the menu's sentence, ranking and bars.
struct MenuDayLeft: Equatable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    /// Food and drinks logged that day against the targets (as Today counts them).
    @MainActor
    init(store: LocalStore, day: Date, calendar: Calendar = .current) {
        guard let profile = store.profile else {
            calories = 0; protein = 0; carbs = 0; fat = 0
            return
        }
        let summary = DaySummary(
            entries: store.foodEntries(on: day, calendar: calendar),
            hydrationLogs: store.hydrationLogs(on: day, calendar: calendar),
            targets: profile.nutritionTargets,
            waterTargetMilliliters: profile.waterTargetMilliliters,
            day: day, now: AppClock.now, calendar: calendar
        )
        calories = max(summary.targets.calories - summary.consumed.calories, 0)
        protein = max(summary.targets.proteinGrams - summary.consumed.proteinGrams, 0)
        carbs = max(summary.targets.carbohydrateGrams - summary.consumed.carbohydrateGrams, 0)
        fat = max(summary.targets.fatGrams - summary.consumed.fatGrams, 0)
    }
}

/// M02: the dishes ranked for the user, the ones that don't fit folded
/// away (never hidden), and several dishes added at once.
struct MenuResultsView: View {
    let result: MenuScanResult
    let day: Date
    let onLogged: () -> Void

    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var filter: MenuRules.Filter = .best
    @State private var chosen: Set<Int> = []
    @State private var portions: [Int: MenuPortion] = [:]
    @State private var showsNotFitting = false
    @State private var openDish: MenuDish?
    @State private var meal = MealType.likely(at: AppClock.now, calendar: .current)
    @State private var showError = false
    @State private var isSaved = false

    var body: some View {
        let left = MenuDayLeft(store: store, day: day)
        let rows = MenuRules.rows(result.dishes, preferences: store.profile?.preferences ?? NutritionPreferences(),
                                  allergies: store.profile?.allergies ?? [])
        let listed = MenuRules.list(rows, filter: filter, caloriesLeft: left.calories, proteinLeft: left.protein,
                                    energyTarget: store.profile?.nutritionTargets.calories ?? 0)
        let notFitting = rows.filter { !$0.fit.fits }
        let best = MenuRules.bestProtein(rows, caloriesLeft: left.calories)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                header(left: left)
                chips(count: rows.count)

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSSectionHeader(title: filterTitle)
                    if listed.isEmpty {
                        Text(filter == .best ? "Nothing on this menu fits you. The dishes are below." : "No dish here.")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .padding(.vertical, VESSSpacing.sm)
                    } else {
                        VESSRowGroup {
                            ForEach(listed) { row in
                                dishRow(row, left: left, isBest: row.id == best)
                            }
                        }
                        .vessListChanges(listed.map(\.id))
                        .vessHairlineBottom()
                    }
                }

                if filter != .all, !notFitting.isEmpty {
                    notFittingSection(notFitting, left: left)
                }

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    if let note = result.note {
                        Text(verbatim: note)
                    }
                    Text("Estimates from dish names and typical restaurant portions, not the kitchen's recipe. Always ask the staff about allergens.")
                }
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
            .padding(.bottom, VESSSpacing.xl)
        }
        .background(VESSColor.background)
        .vessDetailTitle("Menu")
        .vessBottomAction(background: VESSColor.background) {
            if !chosen.isEmpty { addBar }
        }
        .sheet(item: $openDish) { dish in
            MenuDishSheet(
                dish: dish,
                fit: rows.first { $0.id == dish.id }?.fit,
                portion: Binding(get: { portions[dish.id] ?? .regular }, set: { portions[dish.id] = $0 }),
                left: left,
                meal: $meal,
                onAdd: { log([(dish, portions[dish.id] ?? .regular)]) }
            )
        }
        .vessErrorAlert(isPresented: $showError)
    }

    // MARK: Sections

    /// "The evening menu, 10 dishes." and what's left today.
    private func header(left: MenuDayLeft) -> some View {
        let name = result.title?.isEmpty == false ? result.title ?? "" : String(localized: "The menu")
        let dishes = String(AttributedString(localized: "^[\(result.dishes.count) dish](inflect: true)").characters)
        return VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text(verbatim: "\(name), \(dishes).")
                .vessTextStyle(.editorialM)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Group {
                if left.calories > 0 {
                    Text("Estimated per portion from the menu. You have \(VESSFormat.calories(left.calories))\u{00A0}kcal and \(VESSFormat.grams(left.protein))\u{00A0}g protein left today.")
                } else {
                    Text("Estimated per portion from the menu. You've reached today's energy target.")
                }
            }
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chips(count: Int) -> some View {
        VESSBleedingRow {
            HStack(spacing: VESSSpacing.xs) {
                VESSChip(title: "Best for you", isSelected: filter == .best) { setFilter(.best) }
                VESSChip(title: "High-protein", isSelected: filter == .highProtein) { setFilter(.highProtein) }
                VESSChip(title: "Lighter", isSelected: filter == .lighter) { setFilter(.lighter) }
                VESSChip(title: "All \(count)", isSelected: filter == .all) { setFilter(.all) }
            }
        }
        .accessibilityIdentifier("menu.filters")
    }

    private var filterTitle: LocalizedStringResource {
        switch filter {
        case .best: "Best for you"
        case .highProtein: "High-protein"
        case .lighter: "Lighter"
        case .all: "All dishes"
        }
    }

    /// "Doesn't fit you · 6", folded until Show.
    private func notFittingSection(_ rows: [MenuRules.Row], left: MenuDayLeft) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Doesn't fit you · \(rows.count)")
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: VESSSpacing.sm)
                Button {
                    withAnimation(reduceMotion ? nil : VESSMotion.selection) { showsNotFitting.toggle() }
                } label: {
                    HStack(spacing: VESSSpacing.xxs) {
                        Text(showsNotFitting ? "Hide" : "Show")
                        Image(systemName: showsNotFitting ? "chevron.up" : "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu.showNotFitting")
            }
            if showsNotFitting {
                VESSRowGroup {
                    ForEach(rows) { row in dishRow(row, left: left, isBest: false) }
                }
                .vessHairlineBottom()
            }
        }
    }

    /// Name, "≈ 560 kcal · 42 g protein · 14 g carbs", the tag, and the
    /// choose button for dishes that fit. Tap the row for the dish sheet.
    private func dishRow(_ row: MenuRules.Row, left: MenuDayLeft, isBest: Bool) -> some View {
        let nutrition = row.dish.nutrition(portions[row.id] ?? .regular)
        let fits = row.fit.fits
        let isChosen = chosen.contains(row.id)
        return HStack(alignment: .center, spacing: VESSSpacing.sm) {
            Button { openDish = row.dish } label: {
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text(verbatim: row.dish.name)
                        .vessTextStyle(.bodyMStrong)
                        .foregroundStyle(fits ? VESSColor.text : VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(fits
                         ? "≈\u{00A0}\(VESSFormat.calories(nutrition.calories))\u{00A0}kcal · \(VESSFormat.grams(nutrition.proteinGrams))\u{00A0}g protein · \(VESSFormat.grams(nutrition.carbohydrateGrams))\u{00A0}g carbs"
                         : "≈\u{00A0}\(VESSFormat.calories(nutrition.calories))\u{00A0}kcal · \(VESSFormat.grams(nutrition.proteinGrams))\u{00A0}g protein")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(fits ? VESSColor.secondaryText : VESSColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    MenuTag(row: row, calories: nutrition.calories, caloriesLeft: left.calories, isBest: isBest)
                        .padding(.top, VESSSpacing.xxs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, VESSSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the dish")
            if fits {
                VESSIconButton(systemImage: isChosen ? "checkmark" : "plus",
                               label: isChosen ? "Chosen, \(row.dish.name)" : "Choose \(row.dish.name)") {
                    withAnimation(reduceMotion ? nil : VESSMotion.selection) {
                        if isChosen { chosen.remove(row.id) } else { chosen.insert(row.id) }
                    }
                }
                .accessibilityIdentifier("menu.choose.\(row.id)")
            }
        }
        .vessHaptic(.selection, trigger: isChosen)
    }

    /// "2 dishes · 78 g protein / 1 040 kcal · Add to dinner". A long press
    /// on Add picks another meal.
    private var addBar: some View {
        let picked = result.dishes.filter { chosen.contains($0.id) }
        let total = picked.map { $0.nutrition(portions[$0.id] ?? .regular) }.total
        let dishes = String(AttributedString(localized: "^[\(picked.count) dish](inflect: true)").characters)
        return HStack(alignment: .center, spacing: VESSSpacing.md) {
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                Text(verbatim: "\(dishes) · \(VESSFormat.grams(total.proteinGrams))\u{00A0}" + String(localized: "g protein"))
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.secondaryText)
                Text("\(VESSFormat.calories(total.calories))\u{00A0}kcal")
                    .vessTextStyle(.numberRow)
                    .foregroundStyle(VESSColor.text)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Menu {
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.dayOrder) { Text($0.title).tag($0) }
                }
            } label: {
                Text(meal.addToTitle)
            } primaryAction: {
                log(picked.map { ($0, portions[$0.id] ?? .regular) })
            }
            .buttonStyle(.vessPrimary)
            .fixedSize()
            .accessibilityHint("Touch and hold to pick another meal")
            .accessibilityIdentifier("menu.add")
        }
        .padding(.top, VESSSpacing.xs)
    }

    // MARK: Actions

    private func setFilter(_ value: MenuRules.Filter) {
        withAnimation(reduceMotion ? nil : VESSMotion.selection) { filter = value }
    }

    private func log(_ dishes: [(MenuDish, MenuPortion)]) {
        guard !isSaved, let profile = store.profile, !dishes.isEmpty else { return }
        let entries = MenuRules.entries(dishes.map { (dish: $0.0, portion: $0.1) }, menuName: result.title,
                                        userID: profile.id, meal: meal, at: meal.logTime(on: day, calendar: .current))
        isSaved = true
        do {
            for entry in entries { try store.add(entry) }
            undo.show(Text("Added to \(Text(meal.title)) · Estimated")) { store in
                for entry in entries { try store.deleteFoodEntry(id: entry.id) }
            }
            openDish = nil
            onLogged()
        } catch {
            isSaved = false
            showError = true
        }
    }
}

/// The one tag under a dish: why it doesn't fit (grey), "Ask: often has
/// walnuts" or "Low protein" (amber), or "Fits today" (green).
private struct MenuTag: View {
    let row: MenuRules.Row
    let calories: Double
    let caloriesLeft: Double
    let isBest: Bool

    var body: some View {
        let fit = row.fit
        if let allergen = fit.allergens.sorted(by: { $0.rawValue < $1.rawValue }).first {
            VESSTag(text: Text("Has \(Text(allergen.shortTitle))"))
        } else if let reason = fit.reasons.first {
            VESSTag(text: reason.text)
        } else if let hint = fit.hints.first {
            VESSTag(text: Text("Ask: often has \(hint.word)"), tone: .warning)
        } else if calories > caloriesLeft {
            VESSTag(text: Text("Above energy left"), tone: .warning)
        } else if row.dish.nutrition.proteinGrams < MenuRules.lowProteinGrams {
            VESSTag(text: Text("Low protein"), tone: .warning)
        } else if row.dish.confidence == .low {
            VESSTag(text: Text("Fits today · rough estimate"), tone: .positive)
        } else {
            VESSTag(text: isBest ? Text("Fits today · Best protein") : Text("Fits today"), tone: .positive)
        }
    }
}

/// M03: one dish. Portion, the estimate with its confidence, bars against
/// what's left today, what's likely in it and what to ask the staff about.
struct MenuDishSheet: View {
    let dish: MenuDish
    let fit: MenuFit?
    @Binding var portion: MenuPortion
    let left: MenuDayLeft
    @Binding var meal: MealType
    let onAdd: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let nutrition = dish.nutrition(portion)
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text(dish.section.map { "\($0) · " + String(localized: "from the menu") } ?? String(localized: "From the menu"))
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    Text(verbatim: dish.name)
                        .vessTextStyle(.titleL)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let text = dish.menuText {
                        Text("On the menu: “\(text)”")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VESSSegmented(selection: $portion, options: [(.smaller, "Smaller"), (.regular, "Regular"), (.larger, "Larger")])
                    .accessibilityIdentifier("menu.portion")

                // The caption goes under the number at accessibility sizes.
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xxs))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: VESSSpacing.sm))
                layout {
                    Text("≈\u{00A0}\(VESSFormat.calories(nutrition.calories))\u{00A0}kcal")
                        .vessTextStyle(.displayM)
                        .foregroundStyle(VESSColor.text)
                        .contentTransition(.numericText())
                        .fixedSize()
                    Text("estimate · \(Text(dish.confidence.title)) confidence")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    bar("Protein", nutrition.proteinGrams, left: left.protein, metric: .protein)
                    bar("Carbs", nutrition.carbohydrateGrams, left: left.carbs, metric: .carbs)
                    bar("Fat", nutrition.fatGrams, left: left.fat, metric: .fat)
                }

                VESSRowGroup {
                    if !dish.ingredients.isEmpty {
                        VESSListRow(title: Text("Likely in it"), subtitle: Text(verbatim: dish.ingredients.joined(separator: ", ")), showsChevron: false)
                    }
                    if let ask = askText {
                        VESSListRow(title: Text("Ask the staff about"), subtitle: Text(verbatim: ask), showsChevron: false)
                    }
                }
                .vessHairlineBottom()

                if let fit, !fit.fits {
                    Text("Doesn't fit you: \(reasonText(fit)).")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xl)
            .padding(.bottom, VESSSpacing.xl)
        }
        .vessBottomAction {
            Button(action: onAdd) {
                Text("\(Text(meal.addToTitle)) · \(VESSFormat.calories(nutrition.calories))\u{00A0}kcal")
            }
            .buttonStyle(.vessPrimary)
            .accessibilityIdentifier("menu.dish.add")
        }
        .background(VESSColor.card)
        // Opens with the menu still showing above it (M03).
        .presentationDetents([.fraction(0.8), .large])
        // Scrolling moves the content, not the sheet (AX5 needs it).
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    /// "42 g · 58 g left": the hue is this dish's share of what's left.
    private func bar(_ name: LocalizedStringResource, _ grams: Double, left: Double, metric: VESSMetricKind) -> some View {
        VESSMacroBar(
            name: name,
            value: "\(VESSFormat.grams(grams))\u{00A0}g",
            target: left > 0 ? String(localized: "\(VESSFormat.grams(left))\u{00A0}g left") : String(localized: "target reached"),
            adding: left > 0 ? min(grams / left, 1) : 0,
            metric: metric
        )
    }

    /// "Fish · Milk", then the user's allergens it often has: "Tree nuts (often has walnuts)".
    private var askText: String? {
        var parts = dish.allergens.sorted { $0.rawValue < $1.rawValue }.map { String(localized: $0.title) }
        for hint in fit?.hints ?? [] {
            parts.append(String(localized: "\(String(localized: hint.allergen.title)) (often has \(hint.word))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func reasonText(_ fit: MenuFit) -> String {
        if let allergen = fit.allergens.sorted(by: { $0.rawValue < $1.rawValue }).first {
            return String(localized: "has \(String(localized: allergen.shortTitle))")
        }
        return fit.reasons.map { reason -> String in
            switch reason {
            case .has(let content, let ingredient): ingredient ?? String(localized: content.title)
            case .avoid(let item): item.lowercased()
            case .notTagged(let diet): String(localized: "not \(String(localized: diet.title).lowercased())")
            case .meatWithDairy: String(localized: "meat with dairy")
            }
        }.joined(separator: ", ")
    }
}

extension EstimatedItem.Confidence {
    var title: LocalizedStringResource {
        switch self {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        }
    }
}
