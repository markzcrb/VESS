import PhotosUI
import SwiftUI
import UIKit

/// R03: a new recipe, or changes to one of the user's own (or an AI draft).
/// Nutrition per serving is calculated live from the ingredients; diet tags
/// and allergens are worked out from them. The photo stays on this iPhone.
struct RecipeEditorView: View {
    /// `nil` for a new recipe.
    let recipe: Recipe?
    /// Set for an AI draft (R07): the changed draft comes back here instead
    /// of being saved.
    var onDone: ((Recipe) -> Void)?

    @Environment(LocalStore.self) private var store
    @Environment(GenericFoodDatabase.self) private var foods
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: RecipeCategory
    @State private var servings: Int
    @State private var minutes: Int
    @State private var ingredients: [Recipe.Ingredient]
    @State private var steps: [String]
    /// The step number's circle grows with the text.
    @ScaledMetric(relativeTo: .subheadline) private var stepCircle: CGFloat = 28
    @State private var extraAllergens: Set<Allergen> = []
    @State private var photo: Data?
    @State private var removesPhoto = false

    @State private var addsIngredient = false
    @State private var editingIndex: Int?
    @State private var editsServings = false
    @State private var editsTime = false
    @State private var takesPhoto = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var confirmsDiscard = false
    @State private var showError = false
    @State private var keyboardShown = false

    private let calendar = Calendar.current

    init(recipe: Recipe?, onDone: ((Recipe) -> Void)? = nil) {
        self.recipe = recipe
        self.onDone = onDone
        _name = State(initialValue: recipe?.name ?? "")
        _category = State(initialValue: recipe?.category ?? .dinner)
        _servings = State(initialValue: recipe?.servings ?? 2)
        _minutes = State(initialValue: recipe?.minutes ?? 20)
        _ingredients = State(initialValue: recipe?.ingredients ?? [])
        _steps = State(initialValue: recipe?.steps ?? [""])
    }

    var body: some View {
        let draft = completed()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    photoBox

                    VESSTextField("Name", text: $name, prompt: Text("Recipe name"))
                        .accessibilityIdentifier("editor.name")

                    VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                        Text("Meal")
                            .vessTextStyle(.labelCaps)
                            .foregroundStyle(VESSColor.secondaryText)
                        VESSBleedingRow {
                            HStack(spacing: VESSSpacing.xs) {
                                ForEach(RecipeCategory.allCases, id: \.self) { option in
                                    VESSChip(title: option.title, isSelected: category == option) { category = option }
                                }
                            }
                        }
                    }

                    VESSRowGroup {
                        Button { editsServings = true } label: {
                            VESSListRow(title: Text("Servings"), value: Text("\(servings)"))
                        }
                        .buttonStyle(.plain)
                        Button { editsTime = true } label: {
                            VESSListRow(title: Text("Time"), value: Text("\(minutes)\u{00A0}min"))
                        }
                        .buttonStyle(.plain)
                    }
                    .vessHairlineBottom()

                    ingredientList

                    methodList

                    nutritionCard(draft)
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.xs)
                .padding(.bottom, VESSSpacing.huge)
            }
            .scrollDismissesKeyboard(.interactively)
            .vessScreenBackground(nil, clipsUnderBar: false)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .vessDetailTitle(recipe == nil ? "New recipe" : "Edit recipe")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VESSIconButton(systemImage: "xmark", label: "Close") {
                        if hasChanges { confirmsDiscard = true } else { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Hidden while typing, so it never covers what's being edited.
                if !keyboardShown {
                Button(onDone == nil ? "Save recipe" : "Done") { save(draft.recipe) }
                    .buttonStyle(.vessPrimary)
                    .disabled(!canSave)
                    .padding(.horizontal, VESSSpacing.screenInset)
                    .padding(.vertical, VESSSpacing.sm)
                    .background(VESSColor.background)
                    .accessibilityIdentifier("editor.save")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardShown = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardShown = false }
            .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .sheet(isPresented: $addsIngredient) {
                AddIngredientSheet { ingredients.append($0) }
            }
            .sheet(item: Binding(get: { editingIndex.map(EditingIndex.init) }, set: { editingIndex = $0?.index })) { editing in
                AddIngredientSheet(existing: ingredients[editing.index]) { changed in
                    if ingredients.indices.contains(editing.index) { ingredients[editing.index] = changed }
                }
            }
            .sheet(isPresented: $editsServings) {
                NumberEditSheet(title: "Servings", unit: "", value: Double(servings), range: 1...12, step: 1) { servings = Int($0) }
                    .presentationDetents([.height(320)])
            }
            .sheet(isPresented: $editsTime) {
                NumberEditSheet(title: "Time", unit: "min", value: Double(minutes), range: 5...240, step: 5) { minutes = Int($0) }
                    .presentationDetents([.height(320)])
            }
            .fullScreenCover(isPresented: $takesPhoto) {
                CameraPicker { data in
                    takesPhoto = false
                    if let data { setPhoto(data) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { setPhoto(data) }
                    pickerItem = nil
                }
            }
            .task { await foods.load() }
            .vessErrorAlert(isPresented: $showError)
        }
    }

    // MARK: Photo

    @ViewBuilder
    private var photoBox: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
        if let image = currentPhoto {
            VStack(spacing: VESSSpacing.sm) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .overlay { image.resizable().scaledToFill() }
                    .clipShape(shape)
                    .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VESSSpacing.sm) { changeButtons }
                    VStack(spacing: VESSSpacing.sm) { changeButtons }
                }
            }
        } else {
            VStack(spacing: VESSSpacing.sm) {
                Image(systemName: "camera")
                    .font(.title3)
                    .foregroundStyle(VESSColor.secondaryText)
                    .accessibilityHidden(true)
                Text("Add a photo")
                    .vessTextStyle(.bodyMStrong)
                    .foregroundStyle(VESSColor.text)
                Text("Optional. Stays on this iPhone.")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                // Side by side, or stacked at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VESSSpacing.sm) { photoButtons(changeTitle: nil) }
                    VStack(spacing: VESSSpacing.sm) { photoButtons(changeTitle: nil) }
                }
                .padding(.top, VESSSpacing.xs)
            }
            .padding(VESSSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(VESSColor.card, in: shape)
            .overlay(shape.strokeBorder(VESSColor.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }

    @ViewBuilder
    private var changeButtons: some View {
        photoButtons(changeTitle: "Change")
        Button("Remove") { photo = nil; removesPhoto = true }
            .buttonStyle(.vessSecondary)
    }

    @ViewBuilder
    private func photoButtons(changeTitle: LocalizedStringResource?) -> some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button("Camera") { takesPhoto = true }
                .buttonStyle(.vessSecondary)
        }
        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            Text(changeTitle ?? "Library")
        }
        .buttonStyle(.vessSecondary)
        .accessibilityIdentifier("editor.library")
    }

    private var currentPhoto: Image? {
        if let photo, let image = UIImage(data: photo) { return Image(uiImage: image) }
        if !removesPhoto, let recipe { return recipe.photoImage(store: store) }
        return nil
    }

    /// Smaller, without location or camera details, before it's kept.
    private func setPhoto(_ data: Data) {
        photo = PhotoPreparation.jpeg(from: data) ?? data
        removesPhoto = false
    }

    // MARK: Ingredients

    private var ingredientList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ingredients · \(ingredients.count)")
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
                .padding(.bottom, VESSSpacing.xs)
            VESSRowGroup {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ingredient in
                    VESSSwipeToDelete(onTap: { editingIndex = index }, onDelete: { ingredients.remove(at: index) }) {
                        VESSListRow(title: Text(ingredient.name), subtitle: sourceLine(ingredient), value: Text(ingredient.amountText() ?? ""))
                    }
                    .accessibilityHint("Change, or delete")
                }
                Button { addsIngredient = true } label: {
                    HStack(spacing: VESSSpacing.md) {
                        Image(systemName: "plus")
                            .foregroundStyle(VESSColor.text)
                            .accessibilityHidden(true)
                        Text("Add ingredient")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.text)
                        Spacer()
                    }
                    .frame(minHeight: VESSSize.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editor.addIngredient")
            }
            .vessHairlineBottom()
        }
    }

    /// "USDA · generic", "From your pantry · use by Thu", "Open Food Facts".
    private func sourceLine(_ ingredient: Recipe.Ingredient) -> Text {
        let now = AppClock.now
        if let item = store.inventory.first(where: { $0.status == .available && IngredientMatcher.pantryName($0.name, matches: ingredient) }) {
            if item.expirationStatus(now: now, calendar: calendar).needsAttention {
                return Text("From your pantry · \(RecipeText.useBy(item, now: now, calendar: calendar))")
            }
            if ingredient.key == item.name.lowercased() { return Text("From your pantry") }
        }
        switch ingredient.source {
        case .usda: return Text("USDA · generic")
        case .openFoodFacts: return Text("Open Food Facts")
        case .label: return Text("Label values")
        case .user: return Text("Your values")
        case nil: return Text("No nutrition data · Choose food")
        }
    }

    // MARK: Method

    private var methodList: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            Text("Method")
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
            ForEach(steps.indices, id: \.self) { index in
                HStack(alignment: .center, spacing: VESSSpacing.md) {
                    Text("\(index + 1)")
                        .vessTextStyle(.numberS)
                        .foregroundStyle(VESSColor.text)
                        .frame(width: stepCircle, height: stepCircle)
                        .overlay(Circle().strokeBorder(VESSColor.divider))
                        .accessibilityHidden(true)
                    TextField("Step \(index + 1)", text: $steps[index], axis: .vertical)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .accessibilityLabel(Text("Step \(index + 1)"))
                    if steps.count > 1 {
                        Button { steps.remove(at: index) } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(VESSColor.tertiaryText)
                                .frame(width: VESSHitTarget.minimum, height: VESSHitTarget.minimum)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove step \(index + 1)"))
                    }
                }
            }
            Button { steps.append("") } label: {
                Text("Add step")
                    .vessTextStyle(.labelCapsLink)
                    .foregroundStyle(VESSColor.accent)
                    .frame(minHeight: VESSHitTarget.minimum, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor.addStep")
        }
    }

    // MARK: Nutrition

    private func nutritionCard(_ draft: (recipe: Recipe, isPartial: Bool)) -> some View {
        let recipe = draft.recipe
        let nutrition = recipe.nutrition
        return VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            // One line, or two at large sizes, never starting with "·".
            ViewThatFits(in: .horizontal) {
                Text(draft.isPartial ? "Per serving · calculated · partial" : "Per serving · calculated")
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text("Per serving")
                    Text(draft.isPartial ? "Calculated · partial" : "Calculated")
                }
            }
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.secondaryText)
            VStack(alignment: .leading, spacing: VESSSpacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text(VESSFormat.calories(nutrition.calories))
                        .vessTextStyle(.displayM)
                        .foregroundStyle(VESSColor.text)
                    Text("kcal")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                RecipeMacroKey(nutrition: nutrition)
                if let fiber = nutrition.fiberGrams {
                    HStack(spacing: VESSSpacing.xs) {
                        Circle().fill(VESSColor.secondaryText).frame(width: 6, height: 6).accessibilityHidden(true)
                        Text("\(VESSFormat.grams(fiber))\u{00A0}g fibre")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                    }
                }
                if !ingredients.isEmpty {
                    tags(title: "Fits", items: fits(recipe), tone: .positive)
                    allergenTags(recipe)
                }
                Text("Estimates from USDA FoodData Central and Open Food Facts. Diet tags and allergens are worked out from the ingredients.")
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(VESSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VESSColor.card, in: RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider))
        }
    }

    private func fits(_ recipe: Recipe) -> [Text] {
        var items: [Text] = []
        if recipe.dietTags.contains(.vegan) { items.append(Text("Vegan")) }
        if !recipe.dietTags.isDisjoint(with: [.vegan, .vegetarian]) { items.append(Text("Vegetarian")) }
        if recipe.diets.contains(.pescatarian) { items.append(Text("Pescatarian")) }
        if recipe.dietTags.contains(.glutenFree) { items.append(Text("Gluten-free")) }
        if recipe.dietTags.contains(.dairyFree) { items.append(Text("Dairy-free")) }
        return items
    }

    @ViewBuilder
    private func tags(title: LocalizedStringResource, items: [Text], tone: VESSTag.Tone) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                Text(title)
                    .vessTextStyle(.labelCapsS)
                    .foregroundStyle(VESSColor.tertiaryText)
                VESSChipFlow(spacing: VESSSpacing.xs) {
                    ForEach(items.indices, id: \.self) { VESSTag(text: items[$0], tone: tone) }
                }
            }
        }
    }

    /// Allergens from the ingredients can't be removed; the user can add
    /// others (traces, a sauce's allergens) and remove those again.
    private func allergenTags(_ recipe: Recipe) -> some View {
        let fromIngredients = RecipeDerivation.allergens(of: ingredients)
        return VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            Text("Contains")
                .vessTextStyle(.labelCapsS)
                .foregroundStyle(VESSColor.tertiaryText)
            if recipe.allergens.isEmpty {
                Text("None of the 14 allergens")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            VESSChipFlow(spacing: VESSSpacing.xs) {
                ForEach(Allergen.allCases.filter { recipe.allergens.contains($0) }, id: \.self) { allergen in
                    if fromIngredients.contains(allergen) {
                        VESSTag(text: Text(allergen.title), tone: .warning)
                    } else {
                        Button { extraAllergens.remove(allergen) } label: {
                            VESSTag(text: Text("\(Text(allergen.title)) ×"), tone: .warning)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove \(Text(allergen.title))"))
                    }
                }
                Menu {
                    ForEach(Allergen.allCases.filter { !recipe.allergens.contains($0) }, id: \.self) { allergen in
                        Button { extraAllergens.insert(allergen) } label: { Text(allergen.title) }
                    }
                } label: {
                    Text("Add allergen")
                        .vessTextStyle(.labelCapsLink)
                        .foregroundStyle(VESSColor.accent)
                        .frame(minHeight: VESSHitTarget.minimum)
                }
                .accessibilityIdentifier("editor.addAllergen")
            }
        }
    }

    // MARK: Saving

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty
    }

    private var hasChanges: Bool {
        photo != nil || removesPhoto || !extraAllergens.isEmpty
            || name != (recipe?.name ?? "") || category != (recipe?.category ?? .dinner) || servings != (recipe?.servings ?? 2)
            || minutes != (recipe?.minutes ?? 20) || ingredients != (recipe?.ingredients ?? []) || steps != (recipe?.steps ?? [""])
    }

    /// The recipe as it stands, with nutrition, tags and allergens worked out.
    private func completed() -> (recipe: Recipe, isPartial: Bool) {
        let base = Recipe(
            id: recipe?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category, minutes: minutes, extraTime: recipe?.extraTime, servings: servings,
            nutrition: .zero, ingredients: ingredients,
            steps: steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
            tip: recipe?.tip, dietTags: [], tags: recipe?.tags ?? [], highProtein: false, contains: [], allergens: [],
            photo: nil, origin: recipe?.origin == .ai ? .ai : .user, createdAt: recipe?.createdAt ?? AppClock.now
        )
        let extra = extraAllergens.union((recipe?.allergens ?? []).subtracting(RecipeDerivation.allergens(of: recipe?.ingredients ?? [])))
        return RecipeDerivation.complete(base, extraAllergens: extra) { foods.food(ndb: $0)?.per100g }
    }

    private func save(_ recipe: Recipe) {
        if let onDone {
            onDone(recipe)
            dismiss()
            return
        }
        do {
            try store.save(recipe, photo: photo, removePhoto: removesPhoto)
            dismiss()
        } catch {
            showError = true
        }
    }
}

private struct EditingIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

/// The camera, for a recipe photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Data?) -> Void

        init(onFinish: @escaping (Data?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
