import SwiftUI

/// Plan › Recipes: My recipes, Discover (R01) and AI Chef (R05) as text tabs.
struct RecipesContent: View {
    enum Tab: Hashable { case mine, discover, chef }

    @State private var tab: Tab = .discover

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            VESSTextTabs(selection: $tab, options: [(.mine, "My recipes"), (.discover, "Discover"), (.chef, "AI Chef")])
                // Closer to the segments above than Plan's section gap (R01).
                .padding(.top, -VESSSpacing.xl)
            switch tab {
            case .mine: MyRecipesContent()
            case .discover: DiscoverContent()
            case .chef: AIChefContent { tab = .mine }
            }
        }
    }
}

/// R01: search, the "Fits you" line, meal chips, the featured card,
/// collections, quick breakfasts and the note on hidden recipes.
struct DiscoverContent: View {
    @Environment(LocalStore.self) private var store
    @Environment(RecipeCatalog.self) private var catalog
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var query = ""
    @State private var meal: RecipeDiscover.MealFilter = .all
    @State private var showsWhy = false

    private let calendar = Calendar.current

    var body: some View {
        if let profile = store.profile {
            let preferences = profile.preferences
            let items = RecipeDiscover.items(catalog.recipes, preferences: preferences, allergies: profile.allergies)
            let listed = RecipeDiscover.listed(items, meal: .all, preferences: preferences)

            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                // A short prompt at accessibility sizes, so it never ends in "…".
                VESSSearchField(prompt: dynamicTypeSize.isAccessibilitySize ? "Search" : "Search \(listed.count { $0.fit.fits }) recipes",
                                text: $query) { EmptyView() }
                    .accessibilityIdentifier("discover.search")

                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    searchResults(items: items, preferences: preferences)
                } else {
                    fitsLine(profile)
                    mealChips
                    if meal == .all {
                        overview(items: items, preferences: preferences)
                    } else {
                        RecipeRows(items: RecipeDiscover.listed(items, meal: meal, preferences: preferences))
                    }
                    hiddenNote(RecipeDiscover.hidden(items, preferences: preferences))
                }
            }
        }
    }

    // MARK: Parts

    private func fitsLine(_ profile: UserProfile) -> some View {
        // Edit goes under the line at accessibility sizes.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: VESSSpacing.sm))
        return layout {
            Text(RecipeText.fitsYou(profile))
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            NavigationLink { NutritionPreferencesView() } label: {
                Text("Edit")
                    .vessTextStyle(.labelCapsLink)
                    .foregroundStyle(VESSColor.accent)
                    .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit nutrition preferences"))
            .accessibilityIdentifier("discover.editPreferences")
        }
    }

    private var mealChips: some View {
        VESSBleedingRow {
            HStack(spacing: VESSSpacing.xs) {
                ForEach(RecipeDiscover.MealFilter.allCases, id: \.self) { filter in
                    VESSChip(title: filter.title, isSelected: meal == filter) { meal = filter }
                }
            }
        }
    }

    @ViewBuilder
    private func overview(items: [RecipeDiscover.Item], preferences: NutritionPreferences) -> some View {
        let now = AppClock.now
        let times = RecipeDiscover.mealTimes(preferences: preferences) { meal in
            store.foodEntries(from: calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: calendar.startOfDay(for: now)) ?? now, to: now)
                .usualTime(for: meal, calendar: calendar)
        }
        let next = RecipeDiscover.nextMeal(now: now, times: times, calendar: calendar)
        if let featured = RecipeDiscover.featured(items, meal: next.meal, day: next.day, preferences: preferences, calendar: calendar),
           let item = items.first(where: { $0.id == featured.id }) {
            NavigationLink { RecipeView(recipe: catalog.recipe(id: item.id) ?? item.recipe) } label: {
                VESSRecipeCard(
                    size: .large,
                    photo: item.recipe.photoImage(store: store),
                    kicker: featuredKicker(item.recipe, next: next, now: now),
                    title: Text(item.recipe.name),
                    meta: item.recipe.metaLine,
                    badges: RecipeText.badges(for: item.recipe, fit: item.fit, pantry: store.inventory, now: now, calendar: calendar)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("discover.featured")
        }

        let collections = RecipeDiscover.collections(items, preferences: preferences)
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                HStack {
                    Text("Collections")
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    Spacer()
                    NavigationLink { CollectionsList(items: items, collections: collections) } label: {
                        HStack(spacing: VESSSpacing.xxs) {
                            Text("All")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .frame(minHeight: VESSHitTarget.minimum)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                CollectionGrid {
                    ForEach(collections.prefix(6), id: \.collection) { entry in
                        NavigationLink { collectionList(entry.collection, items: items, preferences: preferences) } label: {
                            CollectionTile(collection: entry.collection, count: entry.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        // With recipes that don't fit shown, they follow, greyed with the reason.
        if preferences.showNonFittingRecipes {
            let others = RecipeDiscover.listed(items, meal: .all, preferences: preferences).filter { !$0.fit.fits && !$0.fit.failsOnlyOnAvoid }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Don't fit you")
                            .vessTextStyle(.labelCaps)
                            .foregroundStyle(VESSColor.secondaryText)
                        Spacer()
                        NavigationLink { RecipeListScreen(title: "Don't fit you", items: others) } label: {
                            HStack(spacing: VESSSpacing.xxs) {
                                Text("See all")
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .frame(minHeight: VESSHitTarget.minimum)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    RecipeRows(items: Array(others.prefix(3)))
                }
            }
        }

        let quick = quickBreakfasts(items, preferences: preferences, now: now)
        if !quick.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Quick breakfasts")
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    Spacer()
                    NavigationLink { RecipeListScreen(title: "Quick breakfasts", items: quick) } label: {
                        HStack(spacing: VESSSpacing.xxs) {
                            Text("See all")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .frame(minHeight: VESSHitTarget.minimum)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                RecipeRows(items: Array(quick.prefix(3)))
            }
        }
    }

    /// "TONIGHT · DINNER · PESCATARIAN".
    private func featuredKicker(_ recipe: Recipe, next: (meal: MealType, day: Date), now: Date) -> Text {
        let isToday = calendar.isDate(next.day, inSameDayAs: now)
        let when: LocalizedStringResource = if !isToday { "Tomorrow" } else if next.meal == .dinner { "Tonight" } else { "Today" }
        if let diet = recipe.dietLabel {
            return Text("\(Text(when)) · \(Text(next.meal.title)) · \(Text(diet))")
        }
        return Text("\(Text(when)) · \(Text(next.meal.title))")
    }

    /// Breakfasts and smoothies ready in 15 minutes, with no waiting time,
    /// those using the most from the pantry first.
    private func quickBreakfasts(_ items: [RecipeDiscover.Item], preferences: NutritionPreferences, now: Date) -> [RecipeDiscover.Item] {
        RecipeDiscover.listed(items, meal: .all, preferences: preferences)
            .filter { $0.fit.fits && [.breakfast, .smoothie].contains($0.recipe.category) && $0.recipe.minutes <= 15 && $0.recipe.extraTime == nil }
            .map { ($0, AIChef.pantryUse($0.recipe, pantry: store.inventory, now: now, calendar: calendar)) }
            .sorted { lhs, rhs in
                if lhs.1.useSoon.count != rhs.1.useSoon.count { return lhs.1.useSoon.count > rhs.1.useSoon.count }
                return lhs.1.shareAtHome > rhs.1.shareAtHome
            }
            .map(\.0)
    }

    private func collectionList(_ collection: RecipeDiscover.Collection, items: [RecipeDiscover.Item], preferences: NutritionPreferences) -> some View {
        RecipeListScreen(
            title: collection.title,
            items: RecipeDiscover.listed(items, meal: .all, preferences: preferences).filter { collection.contains($0.recipe) }
        )
    }

    @ViewBuilder
    private func searchResults(items: [RecipeDiscover.Item], preferences: NutritionPreferences) -> some View {
        let results = RecipeDiscover.search(query, in: items, preferences: preferences)
        if results.isEmpty {
            Text("No recipes match “\(query.trimmingCharacters(in: .whitespaces))”. Try an ingredient, such as salmon or oats.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, VESSSpacing.lg)
        } else {
            RecipeRows(items: results)
        }
    }

    @ViewBuilder
    private func hiddenNote(_ summary: RecipeDiscover.HiddenSummary) -> some View {
        if summary.total > 0 {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                Text(RecipeText.hidden(summary))
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if showsWhy {
                    Text(RecipeText.why(summary))
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { showsWhy.toggle() } label: {
                    Text(showsWhy ? "Hide" : "Show why")
                        .vessTextStyle(.labelCapsLink)
                        .foregroundStyle(VESSColor.accent)
                        .frame(minHeight: VESSHitTarget.minimum, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("discover.showWhy")
            }
            .padding(.top, VESSSpacing.xs)
        }
    }
}

/// A collection tile: a hue dot, the name and how many fit.
/// Two columns; one at accessibility sizes, so titles never split mid-word.
private struct CollectionGrid<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: VESSSpacing.sm), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
        LazyVGrid(columns: columns, spacing: VESSSpacing.sm) { content }
    }
}

private struct CollectionTile: View {
    let collection: RecipeDiscover.Collection
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            Circle().fill(collection.color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(collection.title)
                .vessTextStyle(.bodyMStrong)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(count) for you")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
        }
        .padding(VESSSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider))
        .accessibilityElement(children: .combine)
    }
}

/// Recipe rows on hairlines; each opens the recipe.
struct RecipeRows: View {
    let items: [RecipeDiscover.Item]

    @Environment(LocalStore.self) private var store
    @Environment(RecipeCatalog.self) private var catalog
    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        VESSRowGroup {
            ForEach(items) { item in
                NavigationLink { RecipeView(recipe: catalog.recipe(id: item.id) ?? store.userRecipes.first { $0.id == item.id } ?? item.recipe) } label: {
                    VESSRecipeCard(
                        size: .row,
                        photo: item.recipe.photoImage(store: store),
                        kicker: item.recipe.kicker,
                        title: Text(item.recipe.name),
                        meta: item.recipe.metaLine,
                        badges: RecipeText.badges(for: item.recipe, fit: item.fit, pantry: store.inventory, now: now, calendar: calendar),
                        isDimmed: !item.fit.fits && !item.fit.failsOnlyOnAvoid
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recipe.row.\(item.id)")
            }
        }
        .vessHairlineBottom()
    }
}

/// A list of recipes on its own screen: a collection, "See all".
struct RecipeListScreen: View {
    let title: LocalizedStringResource
    let items: [RecipeDiscover.Item]

    var body: some View {
        ScrollView {
            RecipeRows(items: items)
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground()
        .vessDetailTitle(title)
        .toolbar(.hidden, for: .tabBar)
    }
}

/// All collections, from "Collections · All".
private struct CollectionsList: View {
    let items: [RecipeDiscover.Item]
    let collections: [(collection: RecipeDiscover.Collection, count: Int)]

    @Environment(LocalStore.self) private var store

    var body: some View {
        let preferences = store.profile?.preferences ?? NutritionPreferences()
        ScrollView {
            VESSRowGroup {
                ForEach(collections, id: \.collection) { entry in
                    NavigationLink {
                        RecipeListScreen(
                            title: entry.collection.title,
                            items: RecipeDiscover.listed(items, meal: .all, preferences: preferences).filter { entry.collection.contains($0.recipe) }
                        )
                    } label: {
                        VESSListRow(title: Text(entry.collection.title), value: Text("\(entry.count) for you"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .vessHairlineBottom()
            .padding(.horizontal, VESSSpacing.screenInset)
        }
        .vessScreenBackground()
        .vessDetailTitle("Collections")
        .toolbar(.hidden, for: .tabBar)
    }
}
