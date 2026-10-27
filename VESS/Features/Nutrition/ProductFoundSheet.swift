import SwiftUI

/// F03: a scanned product. Its default portion, what that adds against
/// today's targets, and where the values come from. "Add to Dinner" logs the
/// default portion; Details opens the full Food detail for other amounts.
struct ProductFoundSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLookupService.self) private var lookup
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss

    let food: Food
    let day: Date
    @Binding var meal: MealType
    let onLogged: () -> Void

    @State private var showError = false
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    // No pack shot: VESS shows only the user's own photos.
                    RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                        .fill(VESSColor.fill)
                        .frame(height: 120)
                        .overlay {
                            Image(systemName: "barcode")
                                .font(.title)
                                .foregroundStyle(VESSColor.decorative)
                        }
                        .accessibilityHidden(true)
                    product
                    macros
                    sourceNote
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.xl)
            }
            .background(VESSColor.card)
            // The title and Close stay put while the product scrolls.
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, VESSSpacing.screenInset)
                    .padding(.top, VESSSpacing.xl)
                    .padding(.bottom, VESSSpacing.sm)
                    .background(VESSColor.card)
            }
            .safeAreaInset(edge: .bottom) { actions }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
        .vessErrorAlert(isPresented: $showError, retry: add)
    }

    private var header: some View {
        HStack {
            Text("Product found")
                .vessTextStyle(.titleL)
                .foregroundStyle(VESSColor.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
        }
    }

    /// Name, "Brand · 150 g pot", and the kcal for that portion.
    private var product: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            Text(food.name)
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(food.brand.map { "\($0) · \(food.defaultPortionText)" } ?? food.defaultPortionText)
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
            if nutrition.isReported(.calories) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text(VESSFormat.calories(nutrition.calories))
                        .vessTextStyle(.displayL)
                        .foregroundStyle(VESSColor.text)
                    Text("kcal per portion")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .padding(.top, VESSSpacing.sm)
            }
        }
    }

    private var macros: some View {
        let targets = store.profile?.nutritionTargets
        return VStack(spacing: VESSSpacing.lg) {
            bar("Protein", .protein, nutrition.proteinGrams, target: targets?.proteinGrams ?? 0, metric: .protein)
            bar("Carbs", .carbohydrates, nutrition.carbohydrateGrams, target: targets?.carbohydrateGrams ?? 0, metric: .carbs)
            bar("Fat", .fat, nutrition.fatGrams, target: targets?.fatGrams ?? 0, metric: .fat)
        }
    }

    private func bar(_ name: LocalizedStringResource, _ nutrient: CoreNutrient, _ grams: Double, target: Double, metric: VESSMetricKind) -> some View {
        guard nutrition.isReported(nutrient) else {
            return VESSMacroBar(name: name, value: String(localized: "Not reported"), target: "", adding: 0, metric: metric)
        }
        return VESSMacroBar(
            name: name,
            value: "\(VESSFormat.quantity(grams))\u{00A0}g",
            target: target > 0 ? "/ \(VESSFormat.grams(target))\u{00A0}g" : "",
            adding: target > 0 ? grams / target : 0,
            metric: metric
        )
    }

    /// Where the values come from, honestly: never "verified".
    private var sourceNote: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            Text(food.source == .openFoodFacts
                 ? "From Open Food Facts · check against the label"
                 : "From the product database · check against the label")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if food.source == .openFoodFacts {
                Text(OpenFoodFactsClient.attribution)
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(VESSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                .strokeBorder(VESSColor.divider)
        )
    }

    private var actions: some View {
        VStack(spacing: VESSSpacing.sm) {
            NavigationLink {
                FoodDetailView(food: food, day: day, meal: $meal, onLogged: onLogged)
            } label: {
                Text("Details")
            }
            .buttonStyle(.vessSecondary)
            .accessibilityIdentifier("productFound.details")
            Button(action: add) {
                Text(meal.addToTitle)
            }
            .buttonStyle(.vessPrimary)
            .disabled(!food.nutrition.canBeLogged)
            .accessibilityIdentifier("productFound.add")
        }
        .padding(.horizontal, VESSSpacing.screenInset)
        .padding(.vertical, VESSSpacing.sm)
        .background(VESSColor.card)
    }

    private var nutrition: NutritionFacts {
        food.nutrition(forQuantity: food.defaultPortion.baseAmount)
    }

    /// Logs the default portion, offers Undo, and closes the Add flow.
    private func add() {
        guard let profile = store.profile, food.nutrition.canBeLogged else { return }
        let entry = FoodLogEntry(
            userID: profile.id, food: food, portion: food.defaultPortion,
            mealType: meal, loggedAt: meal.logTime(on: day, calendar: calendar)
        )
        do {
            try store.add(entry)
            lookup.cache(food)
            undo.show([entry], meal: meal)
            onLogged()
        } catch {
            showError = true
        }
    }
}
