import SwiftUI

/// Where the Add sheet's Food content can navigate.
enum FoodRoute: Hashable {
    case food(Food)
    /// A scanned code that wasn't found is saved with the new food.
    case createFood(barcode: String?)
    case barcode
}

/// Food in the Add sheet (05, 21): the meal selector, then saved foods when
/// idle and results while typing. Local results (starter catalog, your
/// foods, cached products) appear instantly and work offline; Open Food
/// Facts results are added below them when online. Tapping a food opens
/// its detail; its + button selects it, and the sticky bar logs every
/// selected food with its default portion.
struct FoodSearchHome: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(LocalStore.self) private var store
    @Environment(FoodLookupService.self) private var lookup
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss

    let day: Date
    @Binding var meal: MealType
    @Binding var path: [FoodRoute]

    @State private var query = ""
    @State private var collection: FoodCollection
    @State private var online: OnlineState = .idle
    @State private var selected: [Food] = []
    @State private var showError = false
    @State private var showScanner = false
    /// Where to go once the scanner has closed.
    @State private var afterScanner: AfterScanner?
    @FocusState private var isSearchFocused: Bool

    private enum AfterScanner {
        case logged, typeNumber
        case addManually(barcode: String)
    }

    private let calendar = Calendar.current

    init(day: Date, meal: Binding<MealType>, path: Binding<[FoodRoute]>, collection: FoodCollection) {
        self.day = day
        _meal = meal
        _path = path
        _collection = State(initialValue: collection)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                mealSelector
                searchField
                if trimmedQuery.isEmpty {
                    collectionChips
                    actions
                    savedFoods
                } else {
                    results
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty { selectionBar }
        }
        .animation(reduceMotion ? VESSMotion.reducedCrossfade : VESSMotion.selection, value: selected.count)
        .task(id: trimmedQuery) { await searchOnline() }
        .vessErrorAlert(isPresented: $showError, retry: addSelected)
        .fullScreenCover(isPresented: $showScanner, onDismiss: continueAfterScanner) {
            BarcodeScannerView(
                day: day,
                meal: $meal,
                onLogged: { closeScanner(then: .logged) },
                onTypeNumber: { closeScanner(then: .typeNumber) },
                onAddManually: { code in closeScanner(then: .addManually(barcode: code)) }
            )
        }
    }

    private func closeScanner(then next: AfterScanner) {
        afterScanner = next
        showScanner = false
    }

    private func continueAfterScanner() {
        switch afterScanner {
        case .logged: dismiss()
        case .typeNumber: path.append(.barcode)
        case .addManually(let code): path.append(.createFood(barcode: code))
        case nil: break
        }
        afterScanner = nil
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Header

    /// "To dinner ⌄ · Today · 19:30": the meal is a menu so it can change
    /// without leaving. At accessibility sizes the time goes under it.
    private var mealSelector: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        let time = meal.logTime(on: day, calendar: calendar)
        return layout {
            Menu {
                Picker("Meal", selection: $meal) {
                    ForEach(MealType.dayOrder) { meal in
                        Text(meal.title).tag(meal)
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text(meal.toTitle)
                        .vessTextStyle(.titleL)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .foregroundStyle(VESSColor.text)
                .frame(minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Meal: \(Text(meal.title))"))
            .accessibilityIdentifier("mealPicker")
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: VESSSpacing.sm)
            }
            Group {
                if calendar.isDate(day, inSameDayAs: AppClock.now) {
                    Text("Today · \(time, format: .dateTime.hour().minute())")
                } else {
                    Text("\(day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)) · \(time, format: .dateTime.hour().minute())")
                }
            }
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
        }
    }

    private var searchField: some View {
        HStack(spacing: VESSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VESSColor.secondaryText)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityHidden(true)
            // The placeholder is drawn here: the system one is under 4.5:1,
            // and a custom prompt loses the scaled font at large sizes.
            TextField("Search foods or brands", text: $query, prompt: Text(verbatim: ""))
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
                .background(alignment: .leading) {
                    if query.isEmpty {
                        Text("Search foods or brands")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.tertiaryText)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                }
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier("foodSearch.query")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(VESSColor.tertiaryText)
                        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            Rectangle()
                .fill(VESSColor.divider)
                .frame(width: 1, height: VESSSpacing.xl)
                .accessibilityHidden(true)
            Button {
                showScanner = true
            } label: {
                Image(systemName: "barcode")
                    .foregroundStyle(VESSColor.text)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scan a barcode")
            .accessibilityIdentifier("foodSearch.barcode")
        }
        .padding(.leading, VESSSpacing.md)
        .padding(.trailing, VESSSpacing.xxs)
        .frame(minHeight: VESSHitTarget.control)
        .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous).strokeBorder(VESSColor.divider))
    }

    // MARK: Idle

    /// Bleeds off the edge rather than being cut at the margin (21).
    private var collectionChips: some View {
        VESSBleedingRow {
            HStack(spacing: VESSSpacing.xs) {
                ForEach(FoodCollection.allCases) { item in
                    VESSChip(title: item.title, isSelected: collection == item) {
                        collection = item
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("foodSearch.collection")
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: "Other ways to add")
            // Quick add, Photo and Cycle are tiles in the carousel now.
            VESSRowGroup {
                actionRow("Create a food", detail: "Save your own food or recipe", symbol: "square.and.pencil", route: .createFood(barcode: nil), identifier: "foodSearch.createFood")
            }
            .vessHairlineBottom()
        }
    }

    private func actionRow(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey,
        symbol: String,
        route: FoodRoute,
        identifier: String
    ) -> some View {
        Button {
            path.append(route)
        } label: {
            VESSListRow(systemImage: symbol, title: Text(title), subtitle: Text(detail))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var savedFoods: some View {
        let foods = foods(in: collection)
        return VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: collection.title)
            if foods.isEmpty {
                Text(collection.emptyText)
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, VESSSpacing.xs)
            } else {
                foodList(foods)
            }
        }
    }

    private func foods(in collection: FoodCollection) -> [Food] {
        switch collection {
        case .recent: store.recentFoods()
        case .favorites: store.favoriteFoods()
        case .mine: store.customFoods()
        }
    }

    // MARK: Searching

    @ViewBuilder
    private var results: some View {
        let local = store.searchLocalFoods(trimmedQuery)
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: "On this iPhone")
            if local.isEmpty {
                Text("No saved or common foods match \u{201C}\(trimmedQuery)\u{201D}.")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                foodList(local)
            }
        }
        onlineSection(excluding: Set(local.map(\.id)))
    }

    @ViewBuilder
    private func onlineSection(excluding localIDs: Set<UUID>) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSSectionHeader(title: "Open Food Facts")
            Group {
                switch online {
                case .idle:
                    Text("Type at least 3 letters to search packaged products online.")
                case .searching:
                    HStack(spacing: VESSSpacing.sm) {
                        ProgressView()
                        Text("Searching…")
                    }
                case .results(let foods):
                    let remaining = foods.filter { !localIDs.contains($0.id) }
                    if remaining.isEmpty {
                        Text("No other products found.")
                    } else {
                        foodList(remaining)
                    }
                case .failed(let error):
                    Text(Self.message(for: error, hasLocalResults: !localIDs.isEmpty))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("foodSearch.onlineMessage")
                }
            }
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            Text(OpenFoodFactsClient.attribution)
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func searchOnline() async {
        let query = trimmedQuery
        guard query.count >= 3 else {
            online = .idle
            return
        }
        // Wait for typing to pause; a new keystroke cancels this task.
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        online = .searching
        let result = await lookup.searchOnline(query)
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let foods): online = .results(foods)
        case .failure(let error): online = .failed(error)
        }
    }

    /// Points to the foods above only when there are some.
    static func message(for error: FoodProviderError, hasLocalResults: Bool) -> LocalizedStringResource {
        switch (error, hasLocalResults) {
        case (.offline, true): "You're offline. Foods on this iPhone are still available above."
        case (.offline, false): "You're offline. Packaged products can be searched again once you're connected."
        case (.rateLimited, _): "Too many searches in a short time. Try again in a minute."
        case (_, true): "Open Food Facts didn't respond. Foods on this iPhone are still available above."
        case (_, false): "Open Food Facts didn't respond. Try again in a moment."
        }
    }

    // MARK: Rows

    private func foodList(_ foods: [Food]) -> some View {
        VESSRowGroup {
            ForEach(foods) { food in
                foodRow(food)
            }
        }
        .vessHairlineBottom()
    }

    /// Name and "180 g · Brand"; kcal for the default portion; a + that
    /// turns into a filled check when the food is selected.
    private func foodRow(_ food: Food) -> some View {
        let isSelected = selected.contains { $0.id == food.id }
        return HStack(spacing: VESSSpacing.sm) {
            Button {
                path.append(.food(food))
            } label: {
                VESSRow(title: Text(food.name), subtitle: subtitle(for: food)) {
                    if food.nutrition.canBeLogged {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(VESSFormat.calories(defaultNutrition(of: food).calories))
                                .vessTextStyle(.numberS)
                                .foregroundStyle(VESSColor.text)
                            Text("kcal")
                                .vessTextStyle(.caption)
                                .foregroundStyle(VESSColor.tertiaryText)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("foodRow.\(food.name)")

            if food.nutrition.canBeLogged {
                VESSIconButton(
                    systemImage: isSelected ? "checkmark" : "plus",
                    label: isSelected ? "Remove \(food.name) from selection" : "Select \(food.name)",
                    isFilled: isSelected
                ) {
                    toggle(food)
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("foodSelect.\(food.name)")
                .vessHaptic(.selection, trigger: isSelected)
            }
        }
    }

    private func subtitle(for food: Food) -> Text {
        if let brand = food.brand {
            return Text("\(food.defaultPortionText) · \(brand)")
        }
        return Text(food.defaultPortionText)
    }

    // MARK: Selection

    /// "2 ITEMS / 514 kcal · 34 g protein" and "Add to dinner".
    private var selectionBar: some View {
        let total = selected.map(defaultNutrition(of:)).total
        return HStack(spacing: VESSSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("^[\(selected.count) item](inflect: true)")
                    .vessTextStyle(.labelCapsS)
                    .foregroundStyle(VESSColor.secondaryText)
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xxs) {
                    Text(VESSFormat.calories(total.calories))
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                    Text("kcal · \(VESSFormat.grams(total.proteinGrams)) g protein")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Button(action: addSelected) {
                Text(meal.addToTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.vessPrimary)
            .accessibilityIdentifier("foodSearch.addSelected")
        }
        .padding(.horizontal, VESSSpacing.screenInset)
        .padding(.vertical, VESSSpacing.md)
        .frame(maxWidth: .infinity)
        .background(VESSColor.background)
        .overlay(alignment: .top) { VESSHairline() }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    private func defaultNutrition(of food: Food) -> NutritionFacts {
        food.nutrition(forQuantity: food.defaultPortion.baseAmount)
    }

    private func toggle(_ food: Food) {
        if let index = selected.firstIndex(where: { $0.id == food.id }) {
            selected.remove(at: index)
        } else {
            selected.append(food)
        }
    }

    /// Logs each selected food once, with its default portion.
    private func addSelected() {
        guard let profile = store.profile else { return }
        let time = meal.logTime(on: day, calendar: calendar)
        var logged: [FoodLogEntry] = []
        do {
            for food in selected where food.nutrition.canBeLogged {
                let entry = FoodLogEntry(userID: profile.id, food: food, portion: food.defaultPortion, mealType: meal, loggedAt: time)
                try store.add(entry)
                logged.append(entry)
                lookup.cache(food)
            }
            selected = []
            undo.show(logged, meal: meal)
            dismiss()
        } catch {
            showError = true
        }
    }
}

enum FoodCollection: String, CaseIterable, Identifiable {
    case recent, favorites, mine

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .recent: "Recent"
        case .favorites: "Favorites"
        case .mine: "My foods"
        }
    }

    var emptyText: LocalizedStringResource {
        switch self {
        case .recent: "Foods you log appear here. Search above to find one."
        case .favorites: "Tap the heart on a food to keep it here."
        case .mine: "Foods you create appear here."
        }
    }
}

private enum OnlineState {
    case idle
    case searching
    case results([Food])
    case failed(FoodProviderError)
}

#if DEBUG
extension View {
    /// The store plus an offline lookup service, for previews.
    func previewEnvironment(_ store: LocalStore, health: HealthSyncState? = nil) -> some View {
        environment(store)
            .environment(FoodLookupService.preview(store: store))
            .environment(HealthDataStore(state: health ?? .available(MockData.preview.health)))
            .environment(FoodLogUndo())
            .environment(ReminderService(center: nil, defaults: UserDefaults(suiteName: "preview") ?? .standard))
            .environment(AccountStore(config: nil, transport: URLSessionTransport(), store: MemorySessionStore()))
            .environment(AIConsentStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
    }
}
#endif
