import SwiftUI

/// 16: add a habit: suggestions that track themselves, or your own with
/// how often, a category (its dot colour) and an optional reminder (off by
/// default). Editing uses the same sheet.
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
                        nameField
                        frequencySection
                        categorySection
                    }
                    reminderSection
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
            .vessBottomAction {
                Button(editing == nil ? "Add habit" : "Save", action: save)
                    .buttonStyle(.vessPrimary)
                    .disabled(draft == nil)
                    .accessibilityIdentifier("habitSheet.save")
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

    /// Water, protein at breakfast and steps, from data VESS already has.
    private var suggestions: some View {
        let target = store.profile?.waterTargetMilliliters ?? 2000
        let steps = store.profile?.dailyStepsTarget ?? UserProfile.defaultStepsTarget
        let existing = Set(store.habits.compactMap(\.auto).map(AutoKind.init))
        return VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: "Tracks itself from your log")
            VESSRowGroup {
                suggestion(.waterTarget, name: String(localized: "Water \(VESSFormat.liters(fromMilliliters: target)) L"), detail: "From the drinks you log",
                           symbol: "drop", category: .nutrition, isAdded: existing.contains(.water))
                suggestion(.proteinAtBreakfast, name: String(localized: "Protein at breakfast"), detail: "From your breakfast log",
                           symbol: "fish", category: .nutrition, isAdded: existing.contains(.protein))
                suggestion(.steps(steps), name: String(localized: "\(VESSFormat.steps(Double(steps))) steps"), detail: "From Apple Health",
                           symbol: "figure.walk", category: .movement, isAdded: existing.contains(.steps))
            }
            .vessHairlineBottom()
        }
    }

    private enum AutoKind: Hashable {
        case water, protein, steps
        init(_ rule: HabitAutoRule) {
            switch rule {
            case .waterTarget: self = .water
            case .proteinAtBreakfast: self = .protein
            case .steps: self = .steps
            }
        }
    }

    private func suggestion(_ rule: HabitAutoRule, name: String, detail: LocalizedStringResource, symbol: String,
                            category: HabitCategory, isAdded: Bool) -> some View {
        VESSRow(title: Text(verbatim: name), subtitle: Text(detail)) {
            VESSRowIcon(systemImage: symbol)
        } trailing: {
            if isAdded {
                Text("Added")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            } else {
                Button {
                    addSuggestion(rule, name: name, category: category)
                } label: {
                    Text("Add")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.accent)
                        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add \(name)"))
            }
        }
    }

    private var nameField: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous)
        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: editing == nil ? "Or your own" : "Name")
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
                HStack(spacing: VESSSpacing.xs) {
                    VESSChip(title: "On chosen days", isSelected: customKind == .days) { customKind = .days }
                    VESSChip(title: "Times a week", isSelected: customKind == .times) { customKind = .times }
                }
                if customKind == .days {
                    VESSChipFlow {
                        ForEach(orderedWeekdays, id: \.self) { weekday in
                            VESSChip(title: LocalizedStringResource(stringLiteral: calendar.shortStandaloneWeekdaySymbols[weekday - 1]),
                                     isSelected: days.contains(weekday)) {
                                if days.contains(weekday) { days.remove(weekday) } else { days.insert(weekday) }
                            }
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
                    VESSChip(title: option.title, isSelected: category == option) { category = option }
                        .accessibilityIdentifier("habitSheet.category.\(option.rawValue)")
                }
            }
            Text("The category sets the colour of its dots.")
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
    private var draft: Habit? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
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
            createdAt: editing?.createdAt ?? AppClock.now
        )
    }

    private func addSuggestion(_ rule: HabitAutoRule, name: String, category: HabitCategory) {
        let habit = Habit(id: UUID(), name: name, schedule: .daily, category: category, reminder: nil, auto: rule, createdAt: AppClock.now)
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
