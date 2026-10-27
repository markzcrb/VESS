import SwiftUI

/// 16: add a habit, in two parts: Suggestions (one tap, each saying how
/// it's tracked), then Your own (name, icon, how often, an optional count
/// a day and reminder; the category is guessed from the name). Editing
/// uses the same sheet.
struct AddHabitSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.vessHaptics) private var haptics
    @Environment(ReminderService.self) private var reminders
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let editing: Habit?

    private enum Frequency: Hashable { case daily, weekdays, custom }
    private enum CustomKind: Hashable { case days, times }

    @State private var name = ""
    @State private var frequency: Frequency = .daily
    @State private var customKind: CustomKind = .days
    @State private var days: Set<Int> = []
    @State private var times = 2
    @State private var category: HabitCategory = .other
    /// Set once the user picks a category; until then it follows the name.
    @State private var pickedCategory = false
    @State private var symbol: String?
    @State private var timesPerDay = 1
    @State private var reminderOn = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: AppClock.now) ?? AppClock.now
    @State private var showReminder = false
    @State private var confirmDelete = false
    @State private var showError = false

    @ScaledMetric(relativeTo: .body) private var pinnedInset: CGFloat = VESSHitTarget.control + VESSSpacing.xl * 2

    private let calendar = Calendar.current

    init(editing: Habit?) {
        self.editing = editing
        guard let habit = editing else { return }
        _name = State(initialValue: habit.name)
        _category = State(initialValue: habit.category)
        _pickedCategory = State(initialValue: true)
        _symbol = State(initialValue: habit.symbol)
        _timesPerDay = State(initialValue: habit.timesPerDay ?? 1)
        switch habit.schedule {
        case .daily: _frequency = State(initialValue: .daily)
        case .weekdays: _frequency = State(initialValue: .weekdays)
        case .days(let chosen):
            _frequency = State(initialValue: .custom)
            _days = State(initialValue: chosen)
        case .timesPerWeek(let count):
            _frequency = State(initialValue: .custom)
            _customKind = State(initialValue: .times)
            _times = State(initialValue: count)
        }
        if let time = habit.reminder,
           let date = Calendar.current.date(bySettingHour: time.hour ?? 8, minute: time.minute ?? 0, second: 0, of: AppClock.now) {
            _reminderOn = State(initialValue: true)
            _reminderTime = State(initialValue: date)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    header
                    if editing == nil {
                        suggestions
                    }
                    if editing?.auto == nil {
                        VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                            nameField
                            iconSection
                            frequencySection
                            countSection
                            categorySection
                            reminderSection
                        }
                    } else {
                        reminderSection
                    }
                    if editing != nil {
                        Button("Delete habit") { confirmDelete = true }
                            .buttonStyle(.vessQuiet)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("habitSheet.delete")
                    }
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                // The pinned button's height plus spacing, so "Delete habit"
                // scrolls fully clear of it at every text size.
                .padding(.bottom, pinnedInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(VESSColor.card)
            // Pinned above the safe area with a taller scrim, so it never
            // sits on the chips.
            .vessBottomAction(fade: VESSSpacing.xxl) {
                Button(action: save) {
                    if editing != nil {
                        Text("Save")
                    } else if trimmedName.isEmpty {
                        Text("Add")
                    } else {
                        Text("Add «\(trimmedName)»")
                    }
                }
                .buttonStyle(.vessPrimary)
                .disabled(draft == nil)
                .accessibilityIdentifier("habitSheet.save")
            }
            .onChange(of: name) { _, new in
                if !pickedCategory { category = HabitRules.guessCategory(new) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .vessKeyboardDoneButton()
            .vessErrorAlert(isPresented: $showError)
            .confirmationDialog("Delete this habit?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete habit", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its days are removed too.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                Text(editing == nil ? "New habit" : "Edit habit")
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.secondaryText)
                (editing.map { Text(verbatim: $0.name) } ?? Text("Add a habit"))
                    .vessTextStyle(.displayM)
                    .foregroundStyle(VESSColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: VESSSpacing.md)
            VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
        }
    }

    private struct Suggestion: Identifiable {
        let id: String
        let name: String
        let detail: LocalizedStringResource
        let symbol: String
        let category: HabitCategory
        let rule: HabitAutoRule?
        var timesPerDay: Int? = nil
    }

    /// Part 1: one tap each; the line under says how it's tracked.
    private var suggestionItems: [Suggestion] {
        let target = store.profile?.waterTargetMilliliters ?? 2000
        let steps = store.profile?.dailyStepsTarget ?? UserProfile.defaultStepsTarget
        return [
            Suggestion(id: "water", name: String(localized: "Water \(VESSFormat.liters(fromMilliliters: target)) L"), detail: "From the drinks you log",
                       symbol: "drop", category: .nutrition, rule: .waterTarget),
            Suggestion(id: "protein", name: String(localized: "Protein at breakfast"), detail: "From your breakfast log",
                       symbol: "fish", category: .nutrition, rule: .proteinAtBreakfast),
            Suggestion(id: "steps", name: String(localized: "\(VESSFormat.steps(Double(steps))) steps"), detail: "From Apple Health",
                       symbol: "figure.walk", category: .movement, rule: .steps(steps)),
            Suggestion(id: "sleep", name: String(localized: "Sleep 7 h"), detail: "From Apple Health",
                       symbol: "moon", category: .sleep, rule: .sleep(minutes: 7 * 60)),
            Suggestion(id: "mindful", name: String(localized: "10 mindful minutes"), detail: "From Apple Health",
                       symbol: "leaf", category: .other, rule: .mindfulMinutes(10)),
            Suggestion(id: "caffeine", name: String(localized: "No caffeine after \(Self.cutoff.formatted(date: .omitted, time: .shortened))"), detail: "From the drinks you log",
                       symbol: "cup.and.saucer", category: .nutrition, rule: .noCaffeineAfter(hour: 14)),
            Suggestion(id: "fiber", name: String(localized: "Fibre 25 g"), detail: "From your food log",
                       symbol: "carrot", category: .nutrition, rule: .fiber(grams: 25)),
            Suggestion(id: "veg", name: String(localized: "3 portions of veg"), detail: "Tick each one",
                       symbol: "leaf.circle", category: .nutrition, rule: nil, timesPerDay: 3),
            Suggestion(id: "supplements", name: String(localized: "Take supplements"), detail: "From Supplements",
                       symbol: "pills", category: .supplements, rule: .supplementsTaken),
        ]
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: "Suggestions")
            VESSRowGroup {
                ForEach(suggestionItems) { item in
                    suggestion(item, isAdded: isAdded(item))
                }
            }
            .vessHairlineBottom()
        }
    }

    /// Added already: the same kind of rule, or the same name.
    private func isAdded(_ item: Suggestion) -> Bool {
        store.habits.contains { habit in
            if let rule = item.rule, let auto = habit.auto { return Self.sameKind(rule, auto) }
            return habit.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame
        }
    }

    private static func sameKind(_ a: HabitAutoRule, _ b: HabitAutoRule) -> Bool {
        switch (a, b) {
        case (.waterTarget, .waterTarget), (.proteinAtBreakfast, .proteinAtBreakfast), (.steps, .steps), (.sleep, .sleep),
             (.mindfulMinutes, .mindfulMinutes), (.noCaffeineAfter, .noCaffeineAfter), (.fiber, .fiber), (.supplementsTaken, .supplementsTaken):
            true
        default:
            false
        }
    }

    private func suggestion(_ item: Suggestion, isAdded: Bool) -> some View {
        VESSRow(title: Text(verbatim: item.name), subtitle: Text(item.detail)) {
            VESSRowIcon(systemImage: item.symbol)
        } trailing: {
            if isAdded {
                Text("Added")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            } else {
                Button {
                    addSuggestion(item)
                } label: {
                    Text("Add")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.accent)
                        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add \(item.name)"))
            }
        }
    }

    /// 14:00 today, shown in the user's 12/24-hour format.
    private static var cutoff: Date {
        Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: AppClock.now) ?? AppClock.now
    }

    /// The icons offered for your own habit.
    private static let symbols = ["checkmark.circle", "figure.walk", "drop", "leaf", "moon", "book", "pills", "heart"]

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Icon")
            // Four a row, two rows.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: VESSSpacing.xs), count: 4), spacing: VESSSpacing.xs) {
                ForEach(Self.symbols, id: \.self) { option in
                    let isSelected = (symbol ?? Self.symbols[0]) == option
                    Button { symbol = option } label: {
                        Image(systemName: option)
                            .font(.body)
                            .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                            .frame(width: VESSHitTarget.minimum, height: VESSHitTarget.minimum)
                            .background(isSelected ? VESSColor.fill : Color.clear, in: Circle())
                            .overlay(Circle().strokeBorder(isSelected ? VESSColor.borderStrong : VESSColor.divider))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: option))
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    /// "Times a day": once by default; up to 10 ("2× a day").
    private var countSection: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Times a day")
            HStack(spacing: VESSSpacing.md) {
                VESSIconButton(systemImage: "minus", label: "Fewer") { timesPerDay = max(1, timesPerDay - 1) }
                    .disabled(timesPerDay <= 1)
                Text(timesPerDay == 1 ? "Once" : "\(timesPerDay)× a day")
                    .vessTextStyle(.numberRow)
                    .foregroundStyle(VESSColor.text)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                VESSIconButton(systemImage: "plus", label: "More") { timesPerDay = min(10, timesPerDay + 1) }
                    .disabled(timesPerDay >= 10)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Times a day")
            .accessibilityValue(Text("\(timesPerDay)"))
        }
    }

    private var nameField: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous)
        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: editing == nil ? "Your own" : "Name")
            TextField("Habit", text: $name, prompt: Text("e.g. Stretch for 10 minutes").foregroundStyle(VESSColor.tertiaryText))
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
                .textInputAutocapitalization(.sentences)
                .padding(.horizontal, VESSSpacing.md)
                .frame(minHeight: VESSHitTarget.control)
                .background(VESSColor.fill, in: shape)
                .overlay(shape.strokeBorder(VESSColor.divider))
                .accessibilityIdentifier("habitSheet.name")
        }
    }

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "How often")
            VESSSegmented(selection: $frequency, options: [(.daily, "Daily"), (.weekdays, "Weekdays"), (.custom, "Custom")])
            if frequency == .custom {
                // M T W T F S S; "times a week" stays for habits that use it.
                if case .timesPerWeek = editing?.schedule {
                    HStack(spacing: VESSSpacing.xs) {
                        VESSChip(title: "On chosen days", isSelected: customKind == .days) { customKind = .days }
                        VESSChip(title: "Times a week", isSelected: customKind == .times) { customKind = .times }
                    }
                }
                if customKind == .days {
                    HStack(spacing: VESSSpacing.xxs) {
                        ForEach(orderedWeekdays, id: \.self) { weekday in
                            let isOn = days.contains(weekday)
                            Button {
                                if isOn { days.remove(weekday) } else { days.insert(weekday) }
                            } label: {
                                Text(verbatim: calendar.veryShortStandaloneWeekdaySymbols[weekday - 1])
                                    .vessTextStyle(.bodyMStrong)
                                    .foregroundStyle(isOn ? VESSColor.onAccent : VESSColor.text)
                                    .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum)
                                    .background(isOn ? VESSColor.accentFill : VESSColor.fill, in: Circle())
                                    .overlay(Circle().strokeBorder(VESSColor.divider))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: calendar.standaloneWeekdaySymbols[weekday - 1]))
                            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                } else {
                    HStack(spacing: VESSSpacing.md) {
                        VESSIconButton(systemImage: "minus", label: "Fewer") { times = max(1, times - 1) }
                            .disabled(times <= 1)
                        Text("^[\(times) time](inflect: true) a week")
                            .vessTextStyle(.numberRow)
                            .foregroundStyle(VESSColor.text)
                            .contentTransition(.numericText())
                            .frame(maxWidth: .infinity)
                        VESSIconButton(systemImage: "plus", label: "More") { times = min(6, times + 1) }
                            .disabled(times >= 6)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Times a week")
                    .accessibilityValue(Text("\(times)"))
                }
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Category")
            VESSChipFlow {
                ForEach(HabitCategory.allCases, id: \.self) { option in
                    VESSChip(title: option.title, isSelected: category == option) {
                        category = option
                        pickedCategory = true
                    }
                        .accessibilityIdentifier("habitSheet.category.\(option.rawValue)")
                }
            }
            Text("Guessed from the name; change it if it's wrong. It sets the colour of the dots.")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
        }
    }

    /// "Reminder · None ›"; opens a switch and a time. Off by default.
    private var reminderSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { showReminder.toggle() }
            } label: {
                VESSListRow(
                    title: Text("Reminder"),
                    value: reminderOn ? Text(reminderTime, format: .dateTime.hour().minute()) : Text("None")
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("habitSheet.reminder")
            if showReminder {
                ProfileToggleRow(
                    title: Text("Remind me"),
                    subtitle: Text("On this habit's days, only if it isn't done. Never between 22:00 and 07:00."),
                    isOn: $reminderOn
                )
                if reminderOn {
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    if MealReminders.isQuiet(reminderTime, calendar: calendar) {
                        ActivityFootnote(text: Text("This time is in quiet hours, so no reminder will be sent."))
                    }
                }
            }
        }
        .vessHairlineBottom()
    }

    // MARK: Actions

    private var orderedWeekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// The habit to save, or `nil` while something is missing.
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var draft: Habit? {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return nil }
        let schedule: HabitSchedule
        switch frequency {
        case .daily: schedule = .daily
        case .weekdays: schedule = .weekdays
        case .custom:
            if customKind == .times {
                schedule = .timesPerWeek(times)
            } else {
                guard !days.isEmpty else { return nil }
                schedule = .days(days)
            }
        }
        let time = calendar.dateComponents([.hour, .minute], from: reminderTime)
        return Habit(
            id: editing?.id ?? UUID(),
            name: trimmed,
            schedule: editing?.auto == nil ? schedule : (editing?.schedule ?? .daily),
            category: category,
            reminder: reminderOn ? DateComponents(hour: time.hour, minute: time.minute) : nil,
            auto: editing?.auto,
            createdAt: editing?.createdAt ?? AppClock.now,
            timesPerDay: timesPerDay > 1 ? timesPerDay : nil,
            symbol: symbol
        )
    }

    private func addSuggestion(_ item: Suggestion) {
        let habit = Habit(id: UUID(), name: item.name, schedule: .daily, category: item.category, reminder: nil, auto: item.rule,
                          createdAt: AppClock.now, timesPerDay: item.timesPerDay, symbol: item.symbol)
        do {
            try store.save(habit)
            haptics.play(.success)
        } catch {
            showError = true
        }
    }

    private func save() {
        guard let habit = draft else { return }
        Task {
            if habit.reminder != nil {
                _ = await reminders.requestPermissionIfNeeded()
            }
            do {
                try store.save(habit)
                haptics.play(.success)
                await reminders.sync(store: store)
                dismiss()
            } catch {
                showError = true
            }
        }
    }

    private func delete() {
        guard let editing else { return }
        do {
            try store.deleteHabit(id: editing.id)
            haptics.play(.warning)
            Task { await reminders.sync(store: store) }
            dismiss()
        } catch {
            showError = true
        }
    }
}

#if DEBUG
#Preview("Add · Dark") {
    Color.clear
        .sheet(isPresented: .constant(true)) { AddHabitSheet(editing: nil) }
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
#endif
