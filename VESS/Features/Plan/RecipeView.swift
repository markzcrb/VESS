#if DEBUG
import SwiftUI

/// 08: a recipe. DEBUG builds only, on the demo recipes; there is no
/// recipe content in Release yet. Ingredients are checked against the
/// pantry; cost is left out.
struct RecipeView: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe

    @State private var servings: Int
    @State private var showError = false

    private let calendar = Calendar.current

    init(recipe: Recipe) {
        self.recipe = recipe
        _servings = State(initialValue: recipe.servings)
    }

    var body: some View {
        let now = AppClock.now
        let pantry = store.inventory

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                    .fill(VESSColor.fill)
                    .frame(height: 140)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.title)
                            .foregroundStyle(VESSColor.decorative)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    Text("\(Text(recipe.mealType.title)) · \(dietText)")
                        .vessTextStyle(.labelCapsS)
                        .foregroundStyle(VESSColor.tertiaryText)
                    Text(recipe.name)
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                stats
                macroKey

                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    HStack {
                        Text("Ingredients")
                            .vessTextStyle(.labelCaps)
                            .foregroundStyle(VESSColor.secondaryText)
                        Spacer()
                        VESSIconButton(systemImage: "minus", label: "Fewer servings") { servings = max(1, servings - 1) }
                            .disabled(servings <= 1)
                        Text("^[\(servings) serving](inflect: true)")
                            .vessTextStyle(.bodyMStrong)
                            .foregroundStyle(VESSColor.text)
                            .monospacedDigit()
                        VESSIconButton(systemImage: "plus", label: "More servings") { servings = min(12, servings + 1) }
                    }
                    VESSRowGroup {
                        ForEach(recipe.ingredients, id: \.self) { ingredient in
                            ingredientRow(ingredient, status: PantryMatch.status(for: ingredient.name, in: pantry, now: now, calendar: calendar))
                        }
                    }
                    .vessHairlineBottom()
                }

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Method")
                    if recipe.steps.isEmpty {
                        Text("This demo recipe has no method yet.")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.secondaryText)
                    } else {
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.md) {
                                Text("\(index + 1)")
                                    .vessTextStyle(.numberS)
                                    .foregroundStyle(VESSColor.text)
                                    // Grows with Dynamic Type instead of clipping the number.
                                    .frame(minWidth: 28, minHeight: 28)
                                    .overlay(Circle().strokeBorder(VESSColor.divider))
                                Text(step)
                                    .vessTextStyle(.bodyM)
                                    .foregroundStyle(VESSColor.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground()
        .vessDetailTitle("Recipe")
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: VESSSpacing.sm) {
                Button { planForToday() } label: {
                    Text(isPlannedToday
                         ? "Planned for \(now.formatted(.dateTime.weekday(.abbreviated)))"
                         : "Plan for \(now.formatted(.dateTime.weekday(.abbreviated)))")
                }
                .buttonStyle(.vessSecondary)
                .disabled(isPlannedToday)
                .accessibilityIdentifier("recipe.plan")
                Button("Cook & log", action: cookAndLog)
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("recipe.log")
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.vertical, VESSSpacing.sm)
            .background(VESSColor.background)
            .overlay(alignment: .top) { VESSHairline() }
        }
        .vessErrorAlert(isPresented: $showError)
    }

    /// Already planned for today's slot.
    private var isPlannedToday: Bool {
        let today = calendar.startOfDay(for: AppClock.now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return store.plannedMeals(from: today, to: end).contains { $0.source == .recipe(recipe.id) }
    }

    private var dietText: Text {
        if recipe.diets.contains(.vegan) { return Text("Vegan") }
        if recipe.diets.contains(.vegetarian) { return Text("Vegetarian") }
        return Text("Pescatarian")
    }

    /// Minutes and kcal per serving. No cost.
    private var stats: some View {
        HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xxl) {
            stat(Text("\(recipe.minutes)"), label: "minutes")
            stat(Text(VESSFormat.calories(recipe.nutrition.calories)), label: "kcal / serving")
            Spacer(minLength: 0)
        }
        .padding(.vertical, VESSSpacing.md)
        .overlay(alignment: .top) { VESSHairline() }
        .vessHairlineBottom()
    }

    private func stat(_ value: Text, label: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            value
                .vessTextStyle(.displayM)
                .foregroundStyle(VESSColor.text)
            Text(label)
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    /// "● 42 g protein  ● 58 g carbs  ● 21 g fat", reported values only.
    @ViewBuilder
    private var macroKey: some View {
        let parts: [(nutrient: CoreNutrient, grams: Double, name: LocalizedStringResource, color: Color)] = [
            (.protein, recipe.nutrition.proteinGrams, "protein", VESSColor.protein),
            (.carbohydrates, recipe.nutrition.carbohydrateGrams, "carbs", VESSColor.carbs),
            (.fat, recipe.nutrition.fatGrams, "fat", VESSColor.fat),
        ].filter { recipe.nutrition.isReported($0.nutrient) }
        if !parts.isEmpty {
            HStack(spacing: VESSSpacing.lg) {
                ForEach(parts, id: \.nutrient) { part in
                    HStack(spacing: VESSSpacing.xs) {
                        Circle().fill(part.color).frame(width: 6, height: 6).accessibilityHidden(true)
                        Text("\(VESSFormat.grams(part.grams)) g \(Text(part.name))")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                    }
                }
            }
        }
    }

    private func ingredientRow(_ ingredient: Recipe.Ingredient, status: PantryMatch.Status) -> some View {
        VESSRow(title: Text(ingredient.name)) {
            HStack(spacing: VESSSpacing.sm) {
                switch status {
                case .toBuy: VESSTag(text: Text("Missing"), tone: .warning)
                case .inPantry: VESSTag(text: Text("In pantry"))
                case .useSoon:
                    if let date = PantryMatch.item(for: ingredient.name, in: store.inventory)?.expirationDate {
                        VESSTag(text: Text("Use by \(date.formatted(.dateTime.weekday(.abbreviated)))"), tone: .accent)
                    } else {
                        VESSTag(text: Text("Use soon"), tone: .accent)
                    }
                }
                if let amount = ingredient.amountText(scale: Double(servings) / Double(max(recipe.servings, 1))) {
                    Text(amount)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    /// Plans it for today's slot, replacing what was planned there.
    private func planForToday() {
        let today = calendar.startOfDay(for: AppClock.now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        do {
            for existing in store.plannedMeals(from: today, to: end) where existing.mealType == recipe.mealType {
                try store.deletePlannedMeal(id: existing.id)
            }
            try store.save(PlannedMeal(candidate: .init(recipe: recipe), day: today, meal: recipe.mealType, now: AppClock.now, calendar: calendar))
            dismiss()
        } catch {
            showError = true
        }
    }

    /// Logs one serving now, with Undo. Nothing is added to the plan.
    private func cookAndLog() {
        let meal = PlannedMeal(candidate: .init(recipe: recipe), day: AppClock.now, meal: recipe.mealType, now: AppClock.now, calendar: calendar)
        do {
            try PlanLogging.log(meal, store: store, undo: undo, calendar: calendar, markPlanned: false)
            dismiss()
        } catch {
            showError = true
        }
    }
}
#endif
