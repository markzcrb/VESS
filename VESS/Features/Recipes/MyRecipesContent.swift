import SwiftUI

/// R02: the user's own recipes and those saved from AI Chef. Recently
/// cooked first, then the rest in the chosen order. Stays on this iPhone.
struct MyRecipesContent: View {
    @Environment(LocalStore.self) private var store

    enum Sort: CaseIterable {
        case name, recentlyAdded, quickest

        var title: LocalizedStringResource {
            switch self {
            case .name: "A–Z"
            case .recentlyAdded: "Recently added"
            case .quickest: "Quickest"
            }
        }
    }

    @State private var sort: Sort = .name
    @State private var showsEditor = false

    /// How many recently cooked recipes are shown first.
    static let recentCount = 3

    var body: some View {
        let recipes = store.userRecipes
        let cooked = store.cookedRecipes
        let recent = recipes
            .filter { cooked[$0.id] != nil }
            .sorted { (cooked[$0.id]?.last ?? .distantPast) > (cooked[$1.id]?.last ?? .distantPast) }
            .prefix(Self.recentCount)
        let rest = sorted(recipes)
        let fromAI = recipes.count { $0.origin == .ai }

        VStack(alignment: .leading, spacing: VESSSpacing.xl) {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                Text("Your kitchen.")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(recipes.isEmpty
                     ? "Your own recipes and the ones you save from AI Chef live here."
                     : fromAI == 0 ? "^[\(recipes.count) recipe](inflect: true)" : "^[\(recipes.count) recipe](inflect: true) · \(fromAI) saved from AI Chef")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { showsEditor = true } label: {
                Label("New recipe", systemImage: "plus")
            }
            .buttonStyle(.vessPrimary)
            .accessibilityIdentifier("myRecipes.new")

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    VESSSectionHeader(title: "Recently cooked")
                    rows(Array(recent), cooked: cooked, showsCooked: true)
                }
            }

            if !rest.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("All · \(Text(sort.title))")
                            .vessTextStyle(.labelCaps)
                            .foregroundStyle(VESSColor.secondaryText)
                        Spacer()
                        Menu {
                            Picker("Sort", selection: $sort) {
                                ForEach(Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                        } label: {
                            HStack(spacing: VESSSpacing.xxs) {
                                Text("Sort")
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .frame(minHeight: VESSHitTarget.minimum)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("myRecipes.sort")
                    }
                    rows(rest, cooked: cooked, showsCooked: false)
                }
            }

            Text("Recipes you create stay on this iPhone. Nutrition is calculated from USDA FoodData Central and Open Food Facts.")
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fullScreenCover(isPresented: $showsEditor) { RecipeEditorView(recipe: nil) }
    }

    private func sorted(_ recipes: [Recipe]) -> [Recipe] {
        switch sort {
        case .name: recipes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recentlyAdded: recipes.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .quickest: recipes.sorted { $0.minutes != $1.minutes ? $0.minutes < $1.minutes : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private func rows(_ recipes: [Recipe], cooked: [String: (count: Int, last: Date)], showsCooked: Bool) -> some View {
        VESSRowGroup {
            ForEach(recipes) { recipe in
                NavigationLink { RecipeView(recipe: recipe) } label: {
                    VESSRecipeCard(
                        size: .row,
                        photo: recipe.photoImage(store: store),
                        kicker: recipe.kicker,
                        title: Text(recipe.name),
                        meta: Text("\(recipe.minutes) min · ^[\(recipe.servings) serving](inflect: true) · \(VESSFormat.calories(recipe.nutrition.calories)) kcal"),
                        badges: badges(recipe, cookedCount: showsCooked ? cooked[recipe.id]?.count ?? 0 : 0, showsProtein: showsCooked)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("myRecipes.row.\(recipe.id)")
            }
        }
        .vessHairlineBottom()
    }

    /// One tag: saved from AI, else cooked more than once, else protein.
    private func badges(_ recipe: Recipe, cookedCount: Int, showsProtein: Bool) -> [VESSRecipeBadge] {
        if recipe.origin == .ai { return [.init(text: Text("AI · Checked by you"))] }
        if cookedCount >= 2 { return [.init(text: Text("Cooked \(cookedCount)×"))] }
        if showsProtein, recipe.highProtein {
            return [.init(text: Text("\(VESSFormat.grams(recipe.nutrition.proteinGrams)) g protein"), tone: .positive)]
        }
        return []
    }
}
