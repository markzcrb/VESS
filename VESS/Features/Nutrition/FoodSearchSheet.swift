import SwiftUI

/// Where the food sheet can navigate.
enum FoodRoute: Hashable {
    case food(Food)
    case quickAdd
    case createFood
    case barcode
}

/// Find a food and log it to a meal. Local results (starter catalog, your
/// foods, cached products) appear instantly and work offline; Open Food
/// Facts results are added below them when online.
struct FoodSearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    let day: Date
    @State private var meal: MealType
    @State private var path: [FoodRoute] = []

    init(request: AddFoodRequest) {
        self.day = request.day
        _meal = State(initialValue: request.meal)
    }

    var body: some View {
        NavigationStack(path: $path) {
            FoodSearchHome(meal: $meal, path: $path)
                .navigationDestination(for: FoodRoute.self) { route in
                    destination(for: route)
                        .toolbar { closeButton }
                }
                .toolbar { closeButton }
        }
    }

    @ViewBuilder
    private func destination(for route: FoodRoute) -> some View {
        switch route {
        case .food(let food):
            FoodDetailView(food: food, day: day, meal: $meal, onLogged: { dismiss() })
        case .quickAdd:
            QuickAddForm(day: day, meal: $meal, onLogged: { dismiss() })
        case .createFood:
            // Replace the form with the new food, so Back returns to search.
            CustomFoodForm(onSaved: { food in path = [.food(food)] })
        case .barcode:
            BarcodeLookupView(onFound: { food in path.append(.food(food)) })
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) { dismiss() }
        }
    }
}

/// The search screen: actions and saved foods when idle, results while typing.
private struct FoodSearchHome: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLookupService.self) private var lookup

    @Binding var meal: MealType
    @Binding var path: [FoodRoute]

    @State private var query = ""
    @State private var collection: FoodCollection = .recent
    @State private var online: OnlineState = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                MealPickerHeader(title: "Add to", meal: $meal)
                    .padding(.top, VESSSpacing.sm)
                if trimmedQuery.isEmpty {
                    actions
                    savedFoods
                } else {
                    results
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.huge)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(VESSColor.background)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search food or drink")
        .autocorrectionDisabled()
        .task(id: trimmedQuery) { await searchOnline() }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Idle

    private var actions: some View {
        VESSRowGroup {
            actionRow("Quick add", detail: "Log calories without a product", symbol: "bolt", route: .quickAdd, identifier: "foodSearch.quickAdd")
            actionRow("Create a food", detail: "Save your own food or recipe", symbol: "square.and.pencil", route: .createFood, identifier: "foodSearch.createFood")
            actionRow("Enter a barcode", detail: "Look up a packaged product", symbol: "barcode", route: .barcode, identifier: "foodSearch.barcode")
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
            VESSRow(title: Text(title), subtitle: Text(detail), titleStyle: .rowTitle) {
                VESSThumbnail(systemImage: symbol, isAction: true)
            } trailing: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(VESSColor.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var savedFoods: some View {
        let foods = foods(in: collection)
        return VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Picker("Show", selection: $collection) {
                ForEach(FoodCollection.allCases) { collection in
                    Text(collection.title).tag(collection)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("foodSearch.collection")

            if foods.isEmpty {
                Text(collection.emptyText)
                    .vessTextStyle(.secondary)
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
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            VESSSectionHeader(title: "On this iPhone")
            if local.isEmpty {
                Text("No saved or common foods match \u{201C}\(trimmedQuery)\u{201D}.")
                    .vessTextStyle(.secondary)
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
            switch online {
            case .idle:
                Text("Type at least 3 letters to search packaged products online.")
                    .vessTextStyle(.secondary)
            case .searching:
                HStack(spacing: VESSSpacing.sm) {
                    ProgressView()
                    Text("Searching…")
                        .vessTextStyle(.secondary)
                }
            case .results(let foods):
                let remaining = foods.filter { !localIDs.contains($0.id) }
                if remaining.isEmpty {
                    Text("No other products found.")
                        .vessTextStyle(.secondary)
                } else {
                    foodList(remaining)
                }
            case .failed(let error):
                Text(Self.message(for: error))
                    .vessTextStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("foodSearch.onlineMessage")
            }
            Text(OpenFoodFactsClient.attribution)
                .vessTextStyle(.label)
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

    static func message(for error: FoodProviderError) -> LocalizedStringResource {
        switch error {
        case .offline: "You're offline. Foods on this iPhone are still available above."
        case .rateLimited: "Too many searches in a short time. Try again in a minute."
        default: "Open Food Facts didn't respond. Foods on this iPhone are still available above."
        }
    }

    // MARK: Rows

    private func foodList(_ foods: [Food]) -> some View {
        VESSRowGroup {
            ForEach(foods) { food in
                Button {
                    path.append(.food(food))
                } label: {
                    VESSRow(title: Text(food.name), subtitle: subtitle(for: food)) {
                        if food.nutrition.canBeLogged {
                            Text("\(VESSFormat.calories(food.nutrition(forQuantity: food.defaultPortion.baseAmount).calories)) kcal")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(VESSColor.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("foodRow.\(food.name)")
            }
        }
    }

    private func subtitle(for food: Food) -> Text {
        if let brand = food.brand {
            return Text("\(brand) · \(food.defaultPortionText)")
        }
        return Text(food.defaultPortionText)
    }
}

private enum FoodCollection: String, CaseIterable, Identifiable {
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
    func previewEnvironment(_ store: LocalStore) -> some View {
        environment(store)
            .environment(FoodLookupService.preview(store: store))
    }
}
#endif

#Preview("Search") {
    FoodSearchSheet(request: AddFoodRequest(meal: .lunch, day: .now))
        .previewEnvironment(LocalStore.preview())
}
