import SwiftUI

// MARK: - E01 Goals

/// Direction and daily targets. VESS never changes targets on its own: a
/// suggestion from `NutritionTargetCalculator` is offered, and applied only
/// when the user confirms.
struct GoalsView: View {
    @Environment(LocalStore.self) private var store

    private enum Field: String, Identifiable {
        case calories, protein, carbs, fat, water, steps
        var id: String { rawValue }
    }

    @State private var editing: Field?
    @State private var confirmSuggested = false
    @State private var showError = false

    var body: some View {
        if let profile = store.profile {
            let targets = profile.nutritionTargets
            let suggested = Self.suggestedTargets(for: profile)

            ProfilePage(title: "Goals") {
                ProfileIntro(title: "A guide, not a grade.", text: "VESS shapes your daily targets from these. It never changes them without asking.")

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSSectionHeader(title: "Direction")
                    VESSRowGroup {
                        ForEach(Self.directions(current: profile.effectiveGoal, pregnant: profile.pregnant), id: \.self) { goal in
                            ProfileCheckRow(title: Text(goal.directionTitle), isSelected: profile.effectiveGoal == goal) {
                                update { $0.goal = goal }
                            }
                        }
                    }
                    .vessHairlineBottom()
                }

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSSectionHeader(title: "Daily targets")
                    VESSRowGroup {
                        row(.calories, "Calories", "\(VESSFormat.calories(targets.calories)) kcal")
                        row(.protein, "Protein", "\(VESSFormat.grams(targets.proteinGrams)) g")
                        row(.carbs, "Carbs", "\(VESSFormat.grams(targets.carbohydrateGrams)) g")
                        row(.fat, "Fat", "\(VESSFormat.grams(targets.fatGrams)) g")
                        row(.water, "Water", "\(VESSFormat.liters(fromMilliliters: profile.waterTargetMilliliters)) L")
                        row(.steps, "Steps", VESSFormat.steps(Double(profile.dailyStepsTarget)))
                    }
                    .vessHairlineBottom()
                }

                if let suggested, suggested != targets {
                    VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                        Text("From your body and direction, VESS would suggest \(VESSFormat.calories(suggested.calories)) kcal, \(VESSFormat.grams(suggested.proteinGrams)) g protein, \(VESSFormat.grams(suggested.carbohydrateGrams)) g carbs and \(VESSFormat.grams(suggested.fatGrams)) g fat.")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Use suggested targets") { confirmSuggested = true }
                            .buttonStyle(.vessSecondary)
                            .accessibilityIdentifier("goals.useSuggested")
                    }
                    .confirmationDialog("Use suggested targets?", isPresented: $confirmSuggested, titleVisibility: .visible) {
                        Button("Use suggested targets") { update { $0.nutritionTargets = suggested } }
                    } message: {
                        Text("Your calorie, protein, carb and fat targets change. Water and steps stay as they are.")
                    }
                }

                ActivityFootnote(text: Text("Starting estimates from your answers, not medical advice. Targets are a guide, not a grade."))
            }
            .sheet(item: $editing) { field in
                sheet(field, profile: profile)
            }
            .vessErrorAlert(isPresented: $showError)
        }
    }

    private func row(_ field: Field, _ title: LocalizedStringResource, _ value: String) -> some View {
        Button { editing = field } label: {
            VESSListRow(title: Text(title), value: Text(verbatim: value))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sheet(_ field: Field, profile: UserProfile) -> some View {
        let targets = profile.nutritionTargets
        switch field {
        case .calories:
            NumberEditSheet(title: "Calories", unit: "kcal", value: targets.calories, range: NutritionTargetCalculator.minimumCalories...6000, step: 50) { value in
                update { $0.nutritionTargets.calories = value }
            }
        case .protein:
            NumberEditSheet(title: "Protein", unit: "g", value: targets.proteinGrams, range: 20...400, step: 5) { value in
                update { $0.nutritionTargets.proteinGrams = value }
            }
        case .carbs:
            NumberEditSheet(title: "Carbs", unit: "g", value: targets.carbohydrateGrams, range: 20...800, step: 5) { value in
                update { $0.nutritionTargets.carbohydrateGrams = value }
            }
        case .fat:
            NumberEditSheet(title: "Fat", unit: "g", value: targets.fatGrams, range: 20...300, step: 5) { value in
                update { $0.nutritionTargets.fatGrams = value }
            }
        case .water:
            NumberEditSheet(title: "Water", unit: "L", value: profile.waterTargetMilliliters / 1000, range: 1...6, step: 0.1, fractionDigits: 1) { value in
                update { $0.waterTargetMilliliters = (value * 1000).rounded() }
            }
        case .steps:
            NumberEditSheet(title: "Steps", unit: "", value: Double(profile.dailyStepsTarget), range: 1000...40000, step: 500) { value in
                update { $0.stepsTarget = Int(value) }
            }
        }
    }

    private func update(_ change: (inout UserProfile) -> Void) {
        guard var profile = store.profile else { return }
        change(&profile)
        do { try store.saveProfile(profile) } catch { showError = true }
    }

    /// Lose / Maintain / Gain, plus the current goal if it's another one.
    /// Nothing about losing weight during pregnancy.
    private static func directions(current: WellnessGoal, pregnant: Bool) -> [WellnessGoal] {
        let main: [WellnessGoal] = pregnant ? [.maintainWeight, .gainWeight] : [.loseWeight, .maintainWeight, .gainWeight]
        return main.contains(current) ? main : main + [current]
    }

    /// `nil` without an age, which the formula needs.
    static func suggestedTargets(for profile: UserProfile) -> NutritionTargets? {
        guard let age = profile.age(on: AppClock.now, calendar: .current) else { return nil }
        return NutritionTargetCalculator.targets(for: .init(
            sex: profile.sex,
            ageYears: age,
            heightCentimeters: profile.heightCentimeters,
            weightKilograms: profile.weightKilograms,
            activityLevel: profile.activityLevel,
            goal: profile.effectiveGoal,
            dietaryPreference: profile.preferences.targetDiet
        ))
    }
}

private extension WellnessGoal {
    var directionTitle: LocalizedStringResource {
        switch self {
        case .maintainWeight: "Maintain"
        default: title
        }
    }
}

// MARK: - E02 Body

/// Height, weight, year of birth, sex and activity: the context for the
/// target suggestion on Goals. Weight comes from Apple Health when it has
/// a newer one. H04: BMI for adults (hidden under 18 and during pregnancy),
/// waist and body fat read from Health, and the Pregnant switch.
struct BodyView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    private enum Field: String, Identifiable {
        case height, weight, year
        var id: String { rawValue }
    }

    @State private var editing: Field?
    @State private var showError = false
    @State private var showInfo = false

    private let calendar = Calendar.current

    var body: some View {
        if let profile = store.profile {
            let snapshot = health.state.snapshot
            let healthWeight = snapshot?.latestWeight
            let now = AppClock.now
            let bmi = BodyRules.showsBMI(profile: profile, now: now, calendar: calendar) ? BodyRules.bmi(profile: profile, health: healthWeight) : nil

            ProfilePage(title: "Body") {
                if let bmi {
                    BodyMassIndexSection(bmi: bmi, weight: BodyRules.weight(profile: profile, health: healthWeight), height: profile.heightCentimeters)
                } else {
                    ProfileIntro(title: "The context behind your targets.")
                }

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    if bmi != nil { VESSSectionHeader(title: "Body") }
                    VESSRowGroup {
                        if let healthWeight, healthWeight.measuredAt > profile.updatedAt {
                            VESSListRow(
                                title: Text("Weight"),
                                subtitle: Text("From Apple Health · \(Self.day(healthWeight.measuredAt, now: now, calendar: calendar))"),
                                value: Text("\(VESSFormat.quantity(healthWeight.kilograms)) kg"),
                                showsChevron: false
                            )
                        } else {
                            edit(.weight, "Weight", "\(VESSFormat.quantity(profile.weightKilograms)) kg")
                        }
                        edit(.height, "Height", "\(VESSFormat.quantity(profile.heightCentimeters)) cm")
                        // Read only, and only when Health has a value.
                        if let waist = snapshot?.waist {
                            VESSListRow(
                                title: Text("Waist"),
                                subtitle: Text("From Apple Health · \(Self.day(waist.measuredAt, now: now, calendar: calendar))"),
                                value: Text("\(VESSFormat.quantity(waist.value)) cm"),
                                showsChevron: false
                            )
                        }
                        if let fat = snapshot?.bodyFat {
                            VESSListRow(
                                title: Text("Body fat"),
                                subtitle: Text("From Apple Health · \(Self.day(fat.measuredAt, now: now, calendar: calendar))"),
                                value: Text("\(VESSFormat.quantity(fat.value)) %"),
                                showsChevron: false
                            )
                        }
                        edit(.year, "Year of birth", profile.dateOfBirth.map { String(calendar.component(.year, from: $0)) } ?? "—")
                        menuRow(title: "Sex", subtitle: "Used only to estimate energy needs", value: Text(profile.sex.title)) {
                            ForEach(Sex.allCases, id: \.self) { sex in
                                Button { update { $0.sex = sex } } label: { Text(sex.title) }
                            }
                        }
                        menuRow(title: "Activity level", value: Text(profile.activityLevel.title)) {
                            ForEach(ActivityLevel.allCases, id: \.self) { level in
                                Button { update { $0.activityLevel = level } } label: { Text(level.title) }
                            }
                        }
                        if profile.canBePregnant {
                        ProfileToggleRow(
                            title: Text("Pregnant"),
                            subtitle: Text("Hides BMI and anything about losing weight. Stored on this iPhone; Coach is told, so it never suggests losing weight."),
                            isOn: Binding(get: { profile.pregnant }, set: { isOn in update { $0.isPregnant = isOn } })
                        )
                        .accessibilityIdentifier("body.pregnant")
                        }
                    }
                    .vessHairlineBottom()
                }

                if bmi != nil {
                    let trend = BodyRules.trend(snapshot?.weights ?? [], heightCentimeters: profile.heightCentimeters)
                    if trend.count >= 2 {
                        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                            VESSSectionHeader(title: "BMI · 12 weeks")
                            BodyTrendLine(points: trend)
                        }
                    }
                }

                ActivityFootnote(text: healthWeight == nil
                    ? Text("Body settings help estimate your needs. Changing them doesn't change your targets; Goals shows a suggestion you can use.")
                    : Text("Body settings help estimate your needs. Weight, waist and body fat are read from Apple Health. Changing these doesn't change your targets; Goals shows a suggestion you can use."))
                ActivityFootnote(text: Text("Adults only. BMI isn't shown for under-18s or during pregnancy, and VESS never sets goals from BMI alone."))
            }
            .toolbar {
                // Only with the BMI section it explains.
                if bmi != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        HealthInfoButton(label: "About BMI") { showInfo = true }
                    }
                }
            }
            .sheet(isPresented: $showInfo) {
                HealthInfoSheet(title: "About BMI", notes: [
                    "BMI is your weight in kilograms divided by your height in metres, squared. The ranges are the WHO's adult ranges.",
                    "It's a rough guide: it doesn't tell muscle from fat. VESS shows it only to adults, never during pregnancy, and never sets goals from it alone.",
                    "When Apple Health has a weight newer than the one in your profile, that weight is used.",
                ])
            }
            .sheet(item: $editing) { field in
                switch field {
                case .height:
                    NumberEditSheet(title: "Height", unit: "cm", value: profile.heightCentimeters, range: 100...250, step: 1) { value in
                        update { $0.heightCentimeters = value }
                    }
                case .weight:
                    NumberEditSheet(title: "Weight", unit: "kg", value: profile.weightKilograms, range: 30...300, step: 0.1, fractionDigits: 1) { value in
                        update { $0.weightKilograms = value }
                    }
                case .year:
                    let current = profile.dateOfBirth.map { calendar.component(.year, from: $0) } ?? 1990
                    let thisYear = calendar.component(.year, from: AppClock.now)
                    NumberEditSheet(title: "Year of birth", unit: "", value: Double(current), range: Double(thisYear - 100)...Double(thisYear - 16), step: 1, grouping: false) { value in
                        update { $0.dateOfBirth = Self.date(of: $0.dateOfBirth, inYear: Int(value), calendar: calendar) }
                    }
                }
            }
            .vessErrorAlert(isPresented: $showError)
        }
    }

    /// "today", or "12 Oct".
    private static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? String(localized: "today")
            : date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func edit(_ field: Field, _ title: LocalizedStringResource, _ value: String) -> some View {
        Button { editing = field } label: {
            VESSListRow(title: Text(title), value: Text(verbatim: value))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func menuRow<Items: View>(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, value: Text, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            VESSListRow(title: Text(title), subtitle: subtitle.map { Text($0) }, value: value)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func update(_ change: (inout UserProfile) -> Void) {
        guard var profile = store.profile else { return }
        change(&profile)
        do { try store.saveProfile(profile) } catch { showError = true }
    }

    /// Keeps the day and month; only the year changes.
    private static func date(of birthday: Date?, inYear year: Int, calendar: Calendar) -> Date? {
        var parts = birthday.map { calendar.dateComponents([.month, .day], from: $0) } ?? DateComponents(month: 7, day: 1)
        parts.year = year
        return calendar.date(from: parts)
    }
}

// MARK: - E03 Nutrition preferences

/// Diet, what to avoid, and the usual meal times VESS has learned.
/// P01 (replaces E03): one diet, preferences, the 14 EU allergens, the
/// ingredients the user doesn't eat, whether recipes that don't fit are
/// shown, and the usual meal times.
struct NutritionPreferencesView: View {
    @Environment(LocalStore.self) private var store
    @State private var showError = false
    @State private var addsAvoid = false
    @State private var newAvoid = ""
    @State private var editsMealTimes = false

    private let calendar = Calendar.current

    /// P01's order: the most common allergies first.
    static let allergenOrder: [Allergen] = [
        .peanuts, .nuts, .milk, .eggs, .fish, .crustaceans, .soy, .gluten, .sesame, .celery, .mustard, .lupin, .molluscs, .sulphites,
    ]

    var body: some View {
        if let profile = store.profile {
            let preferences = profile.preferences
            let history = store.foodEntries(
                from: calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: calendar.startOfDay(for: AppClock.now)) ?? AppClock.now,
                to: calendar.startOfDay(for: AppClock.now)
            )
            let times = RecipeDiscover.mealTimes(preferences: preferences) { history.usualTime(for: $0, calendar: calendar) }

            ProfilePage(title: "Nutrition preferences") {
                ProfileIntro(title: "Food that fits your life.")

                chipSection("Diet · one") {
                    ForEach(Diet.allCases, id: \.self) { diet in
                        VESSChip(title: diet.title, isSelected: preferences.diet == diet) {
                            update { $0.diet = diet }
                        }
                    }
                }

                chipSection("Also prefer · any", footnote: "Halal and kosher are read from the ingredients, not from a certification.") {
                    ForEach(FoodPreference.allCases, id: \.self) { preference in
                        VESSChip(title: preference.title, isSelected: preferences.alsoPrefer.contains(preference)) {
                            update { $0.alsoPrefer.formSymmetricDifference([preference]) }
                        }
                    }
                }

                chipSection(
                    "Allergies and intolerances · never shown",
                    footnote: "The 14 allergens food labels must declare in the EU. Recipes and suggestions with any of these are hidden, and foods that list them get a warning."
                ) {
                    ForEach(Self.allergenOrder, id: \.self) { allergen in
                        VESSChip(title: allergen.title, isSelected: profile.allergies.contains(allergen)) {
                            updateProfile { $0.allergies.formSymmetricDifference([allergen]) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    HStack {
                        Text("Ingredients you don't eat")
                            .vessTextStyle(.labelCaps)
                            .foregroundStyle(VESSColor.secondaryText)
                        Spacer()
                        Button { addsAvoid = true } label: {
                            HStack(spacing: VESSSpacing.xxs) {
                                Text("Add")
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .trailing)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("preferences.addAvoid")
                    }
                    if preferences.avoidIngredients.isEmpty {
                        Text("Nothing yet.")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                    } else {
                        VESSChipFlow(spacing: VESSSpacing.xs) {
                            ForEach(preferences.avoidIngredients, id: \.self) { item in
                                VESSChip(title: "\(item) ×", isSelected: true) {
                                    update { $0.avoidIngredients.removeAll { $0 == item } }
                                }
                                .accessibilityLabel(Text("Remove \(item)"))
                            }
                        }
                    }
                    ActivityFootnote(text: Text("Hidden from Discover and never used by AI Chef; when one is only an optional garnish, the recipe stays and leaves it out. Unlike allergies, you can still open a recipe that has them."))
                }

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSSectionHeader(title: "Recipes")
                    VESSRowGroup {
                        ProfileToggleRow(
                            title: Text("Show recipes that don't fit"),
                            subtitle: Text("Shown greyed out with the reason"),
                            isOn: Binding(get: { preferences.showNonFittingRecipes }, set: { on in update { $0.showNonFittingRecipes = on } })
                        )
                        Button { editsMealTimes = true } label: {
                            VESSListRow(title: Text("Usual meal times"), value: Text(Self.timesText(times)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("preferences.mealTimes")
                    }
                    .vessHairlineBottom()
                    ActivityFootnote(text: Text("Always check labels yourself. Recipe allergen tags come from the ingredients and can miss cross-contamination."))
                }
            }
            .alert("Ingredient you don't eat", isPresented: $addsAvoid) {
                TextField("Mushrooms", text: $newAvoid)
                Button("Add") {
                    let item = newAvoid
                    newAvoid = ""
                    update { $0.avoidIngredients = NutritionPreferences.normalizedAvoidList($0.avoidIngredients + [item]) }
                }
                Button("Cancel", role: .cancel) { newAvoid = "" }
            } message: {
                Text("One ingredient, such as coriander or blue cheese.")
            }
            .sheet(isPresented: $editsMealTimes) {
                MealTimesSheet(times: times, isSet: preferences.mealTimes != nil) { set in
                    update { $0.mealTimes = set }
                }
            }
            .vessErrorAlert(isPresented: $showError)
        }
    }

    private func chipSection<Content: View>(_ title: LocalizedStringResource, footnote: LocalizedStringResource? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text(title)
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
            VESSChipFlow(spacing: VESSSpacing.xs) { content() }
            if let footnote {
                ActivityFootnote(text: Text(footnote))
            }
        }
    }

    /// "07:30 · 12:30 · 19:30".
    static func timesText(_ times: MealTimes) -> String {
        [times.breakfast, times.lunch, times.dinner].map(clock).joined(separator: " · ")
    }

    /// In the user's clock format, like the time pickers.
    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date(timeIntervalSinceReferenceDate: 0)) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }

    private func update(_ change: (inout NutritionPreferences) -> Void) {
        updateProfile { profile in
            var preferences = profile.preferences
            change(&preferences)
            profile.nutritionPreferences = preferences
        }
    }

    private func updateProfile(_ change: (inout UserProfile) -> Void) {
        guard var profile = store.profile else { return }
        change(&profile)
        do { try store.saveProfile(profile) } catch { showError = true }
    }
}

/// The three usual meal times, or back to learning them from the log.
private struct MealTimesSheet: View {
    let times: MealTimes
    let isSet: Bool
    let onSave: (MealTimes?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var breakfast: Date
    @State private var lunch: Date
    @State private var dinner: Date

    private static let calendar = Calendar.current

    init(times: MealTimes, isSet: Bool, onSave: @escaping (MealTimes?) -> Void) {
        self.times = times
        self.isSet = isSet
        self.onSave = onSave
        _breakfast = State(initialValue: Self.date(times.breakfast))
        _lunch = State(initialValue: Self.date(times.lunch))
        _dinner = State(initialValue: Self.date(times.dinner))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                VESSRowGroup {
                    picker("Breakfast", $breakfast)
                    picker("Lunch", $lunch)
                    picker("Dinner", $dinner)
                }
                .vessHairlineBottom()
                ActivityFootnote(text: Text("Used to pick the next meal in Discover and AI Chef. Until you set them, they're learned from when you log."))
                if isSet {
                    Button("Learn them from my log") {
                        onSave(nil)
                        dismiss()
                    }
                    .buttonStyle(.vessSecondary)
                }
                Spacer()
                Button("Save") {
                    onSave(MealTimes(breakfast: Self.minutes(breakfast), lunch: Self.minutes(lunch), dinner: Self.minutes(dinner)))
                    dismiss()
                }
                .buttonStyle(.vessPrimary)
                .padding(.bottom, VESSSpacing.sm)
                .accessibilityIdentifier("mealTimes.save")
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.md)
            .background(VESSColor.card)
            .vessDetailTitle("Usual meal times")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
            }
        }
        // Full height: a medium sheet is drawn scaled down, below 44 pt targets.
        .presentationDetents([.large])
        .presentationBackground(VESSColor.card)
    }

    private func picker(_ title: LocalizedStringResource, _ value: Binding<Date>) -> some View {
        DatePicker(selection: value, displayedComponents: .hourAndMinute) {
            Text(title)
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
        }
        .tint(VESSColor.text)
        .frame(minHeight: VESSSize.rowHeight)
    }

    private static func date(_ minutes: Int) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date(timeIntervalSinceReferenceDate: 0)) ?? .now
    }

    private static func minutes(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

// MARK: - Number edit sheet

/// One number with a stepper, saved with Save.
struct NumberEditSheet: View {
    let title: LocalizedStringResource
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    var fractionDigits = 0
    var grouping = true
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value: Double

    init(title: LocalizedStringResource, unit: String, value: Double, range: ClosedRange<Double>, step: Double, fractionDigits: Int = 0, grouping: Bool = true, onSave: @escaping (Double) -> Void) {
        self.title = title
        self.unit = unit
        self.range = range
        self.step = step
        self.fractionDigits = fractionDigits
        self.grouping = grouping
        self.onSave = onSave
        _value = State(initialValue: min(max(value, range.lowerBound), range.upperBound))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: VESSSpacing.xl) {
                HStack {
                    VESSIconButton(systemImage: "minus", label: "Less") { value = max(range.lowerBound, value - step) }
                        .disabled(value <= range.lowerBound)
                    Spacer()
                    Text(verbatim: unit.isEmpty ? formatted : "\(formatted) \(unit)")
                        .vessTextStyle(.displayM)
                        .foregroundStyle(VESSColor.text)
                        .contentTransition(.numericText())
                    Spacer()
                    VESSIconButton(systemImage: "plus", label: "More") { value = min(range.upperBound, value + step) }
                        .disabled(value >= range.upperBound)
                }
                .accessibilityElement(children: .contain)
                .accessibilityValue(Text(verbatim: formatted))

                Button("Save") {
                    onSave(value)
                    dismiss()
                }
                .buttonStyle(.vessPrimary)
                .accessibilityIdentifier("numberEdit.save")
            }
            .padding(VESSSpacing.screenInset)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(VESSColor.card)
            .vessDetailTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    private var formatted: String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).grouping(grouping ? .automatic : .never))
    }
}
