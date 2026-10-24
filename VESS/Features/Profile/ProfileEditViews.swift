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
                        ForEach(Self.directions(current: profile.goal), id: \.self) { goal in
                            ProfileCheckRow(title: Text(goal.directionTitle), isSelected: profile.goal == goal) {
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
    private static func directions(current: WellnessGoal) -> [WellnessGoal] {
        let main: [WellnessGoal] = [.loseWeight, .maintainWeight, .gainWeight]
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
            goal: profile.goal,
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
/// target suggestion on Goals. Weight comes from Apple Health when it has one.
struct BodyView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    private enum Field: String, Identifiable {
        case height, weight, year
        var id: String { rawValue }
    }

    @State private var editing: Field?
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        if let profile = store.profile {
            let healthWeight = health.state.snapshot?.latestWeight

            ProfilePage(title: "Body") {
                ProfileIntro(title: "The context behind your targets.")

                VESSRowGroup {
                    edit(.height, "Height", "\(VESSFormat.quantity(profile.heightCentimeters)) cm")
                    if let healthWeight {
                        VESSListRow(
                            title: Text("Weight"),
                            subtitle: Text("From Apple Health · \(healthWeight.measuredAt, format: .dateTime.day().month(.abbreviated))"),
                            value: Text("\(VESSFormat.quantity(healthWeight.kilograms)) kg"),
                            showsChevron: false
                        )
                    } else {
                        edit(.weight, "Weight", "\(VESSFormat.quantity(profile.weightKilograms)) kg")
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
                }
                .vessHairlineBottom()

                ActivityFootnote(text: healthWeight == nil
                    ? Text("Body settings help estimate your needs. Changing them doesn't change your targets; Goals shows a suggestion you can use.")
                    : Text("Body settings help estimate your needs. Your weight is read from Apple Health. Changing these doesn't change your targets; Goals shows a suggestion you can use."))
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
struct NutritionPreferencesView: View {
    @Environment(LocalStore.self) private var store
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        if let profile = store.profile {
            let history = store.foodEntries(
                from: calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: calendar.startOfDay(for: AppClock.now)) ?? AppClock.now,
                to: calendar.startOfDay(for: AppClock.now)
            )
            ProfilePage(title: "Nutrition preferences") {
                ProfileIntro(title: "Food that fits your life.")

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSSectionHeader(title: "Diet")
                    VESSRowGroup {
                        ForEach(Diet.allCases, id: \.self) { diet in
                            ProfileCheckRow(title: Text(diet.title), isSelected: profile.preferences.diet == diet) {
                                update { var preferences = $0.preferences; preferences.diet = diet; $0.nutritionPreferences = preferences }
                            }
                        }
                    }
                    .vessHairlineBottom()
                }

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSSectionHeader(title: "Avoid")
                    VESSRowGroup {
                        ForEach(Allergen.allCases, id: \.self) { allergen in
                            ProfileToggleRow(title: Text(allergen.title), isOn: Binding(
                                get: { profile.allergies.contains(allergen) },
                                set: { on in update { if on { $0.allergies.insert(allergen) } else { $0.allergies.remove(allergen) } } }
                            ))
                        }
                    }
                    .vessHairlineBottom()
                    ActivityFootnote(text: Text("Plan suggestions skip anything you avoid."))
                }

                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSSectionHeader(title: "Usual meal times")
                    VESSRowGroup {
                        ForEach(MealType.mainMeals, id: \.self) { meal in
                            VESSListRow(title: Text(meal.title), value: Text(Self.timeText(history.usualTime(for: meal, calendar: calendar), calendar: calendar)), showsChevron: false)
                        }
                    }
                    .vessHairlineBottom()
                    ActivityFootnote(text: Text("Learned from when you log, once there are three days. Used for meal regularity and reminders."))
                }
            }
            .vessErrorAlert(isPresented: $showError)
        }
    }

    private static func timeText(_ time: DateComponents?, calendar: Calendar) -> String {
        guard let time, let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: time.hour, minute: time.minute)) else { return "—" }
        return date.formatted(.dateTime.hour().minute())
    }

    private func update(_ change: (inout UserProfile) -> Void) {
        guard var profile = store.profile else { return }
        change(&profile)
        do { try store.saveProfile(profile) } catch { showError = true }
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
