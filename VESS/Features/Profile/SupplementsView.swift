import SwiftUI

/// E04: the user's own supplements and doses, with an optional daily
/// reminder each. VESS records what the user chose and never suggests one.
struct SupplementsView: View {
    @Environment(LocalStore.self) private var store
    @Environment(ReminderService.self) private var reminders
    @Environment(\.openURL) private var openURL

    @State private var editing: Supplement?
    @State private var adding = false
    @State private var showDenied = false
    @State private var showError = false

    var body: some View {
        let supplements = store.supplements

        ProfilePage(title: "Supplements") {
            ProfileIntro(title: "A separate daily rhythm.", text: "Your own supplements and doses, kept apart from food. VESS never suggests one.")

            if supplements.isEmpty {
                Text("No supplements yet.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    VESSSectionHeader(title: "Daily")
                    VESSRowGroup {
                        ForEach(supplements) { supplement in
                            row(supplement)
                        }
                    }
                    .vessHairlineBottom()
                    ActivityFootnote(text: Text("Switch on to get a reminder at its time."))
                }
            }

            if showDenied {
                NotificationsDeniedNote { openSettings() }
            }

            Button("Add supplement") { adding = true }
                .buttonStyle(.vessSecondary)
                .accessibilityIdentifier("supplements.add")
        }
        .sheet(item: $editing) { SupplementEditSheet(supplement: $0) }
        .sheet(isPresented: $adding) { SupplementEditSheet(supplement: nil) }
        .vessErrorAlert(isPresented: $showError)
    }

    private func row(_ supplement: Supplement) -> some View {
        HStack(spacing: VESSSpacing.md) {
            Button { editing = supplement } label: {
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text(supplement.name)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                    supplement.summary
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit")

            // The switch has no visible label; VoiceOver hears the one below.
            Toggle(isOn: Binding(
                get: { supplement.reminderEnabled },
                set: { setReminder($0, for: supplement) }
            )) { EmptyView() }
            .toggleStyle(.vess)
            .fixedSize()
            .accessibilityLabel(Text("Reminder for \(supplement.name)"))
        }
        .padding(.vertical, VESSSpacing.sm)
        .frame(minHeight: VESSSize.rowHeight)
    }

    private func setReminder(_ on: Bool, for supplement: Supplement) {
        guard on else {
            save(supplement, reminder: false)
            return
        }
        // A reminder needs a time; the edit sheet asks for one.
        guard supplement.reminderTime != nil else {
            editing = supplement
            return
        }
        Task {
            if await reminders.requestPermissionIfNeeded() {
                showDenied = false
                save(supplement, reminder: true)
            } else {
                showDenied = true
            }
        }
    }

    private func save(_ supplement: Supplement, reminder: Bool) {
        var updated = supplement
        updated.reminderEnabled = reminder
        do {
            try store.save(updated)
            Task { await reminders.sync(store: store) }
        } catch {
            showError = true
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// Add or edit a supplement: name, dose, and an optional reminder time.
struct SupplementEditSheet: View {
    let supplement: Supplement?

    @Environment(LocalStore.self) private var store

    @Environment(\.vessHaptics) private var haptics
    @Environment(ReminderService.self) private var reminders
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var doseText: String
    @State private var unit: SupplementUnit
    @State private var remind: Bool
    @State private var time: Date
    @State private var showDeleteConfirmation = false
    @State private var showError = false

    init(supplement: Supplement?) {
        self.supplement = supplement
        _name = State(initialValue: supplement?.name ?? "")
        _doseText = State(initialValue: supplement.map { VESSFormat.quantity($0.dosage) } ?? "")
        _unit = State(initialValue: supplement?.unit ?? .milligram)
        _remind = State(initialValue: supplement?.reminderTime != nil)
        let parts = supplement?.reminderTime ?? DateComponents(hour: 8, minute: 0)
        _time = State(initialValue: Calendar.current.date(bySettingHour: parts.hour ?? 8, minute: parts.minute ?? 0, second: 0, of: AppClock.now) ?? AppClock.now)
    }

    private var dose: Double? { VESSFormat.number(from: doseText) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (dose ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    VESSTextField("Name", text: $name)
                    HStack(alignment: .bottom, spacing: VESSSpacing.sm) {
                        VESSTextField("Dose", text: $doseText)
                            .keyboardType(.decimalPad)
                        Menu {
                            ForEach(SupplementUnit.allCases, id: \.self) { option in
                                Button { unit = option } label: { Text(option.abbreviation) }
                            }
                        } label: {
                            HStack(spacing: VESSSpacing.xxs) {
                                Text(unit.abbreviation)
                                Image(systemName: "chevron.up.chevron.down").font(.caption)
                            }
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.text)
                            .frame(minWidth: 72, minHeight: VESSHitTarget.control)
                            .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
                        }
                        .accessibilityLabel(Text("Unit, \(Text(unit.abbreviation))"))
                    }
                    VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                        ProfileToggleRow(title: Text("Daily reminder"), isOn: $remind)
                        if remind {
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                                .vessTextStyle(.bodyM)
                                .foregroundStyle(VESSColor.text)
                        }
                    }
                    Text("VESS records the dose you choose. It doesn't recommend supplements or doses.")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if supplement != nil {
                        Button("Delete") { showDeleteConfirmation = true }
                            .buttonStyle(.vessSecondary)
                            .accessibilityIdentifier("supplement.delete")
                    }
                }
                .padding(VESSSpacing.screenInset)
            }
            .background(VESSColor.card)
            .vessDetailTitle(supplement == nil ? "Add supplement" : "Supplement")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .vessBottomAction {
                Button("Save", action: save)
                    .buttonStyle(.vessPrimary)
                    .disabled(!canSave)
                    .accessibilityIdentifier("supplement.save")
            }
            .confirmationDialog("Delete this supplement?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
            .vessErrorAlert(isPresented: $showError)
        }
        .presentationCornerRadius(VESSRadius.sheet)
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let dose else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let updated = Supplement(
            id: supplement?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            dosage: dose,
            unit: unit,
            schedule: supplement?.schedule ?? .daily,
            reminderTime: remind ? DateComponents(hour: parts.hour, minute: parts.minute) : nil,
            reminderEnabled: remind,
            notes: supplement?.notes
        )
        Task {
            // Turning a reminder on asks for permission the first time.
            var toSave = updated
            if remind, !(supplement?.reminderEnabled ?? false) {
                toSave.reminderEnabled = await reminders.requestPermissionIfNeeded()
            }
            do {
                try store.save(toSave)
                await reminders.sync(store: store)
                dismiss()
            } catch {
                showError = true
            }
        }
    }

    private func delete() {
        guard let supplement else { return }
        do {
            try store.deleteSupplement(id: supplement.id)
            haptics.play(.warning)
            Task { await reminders.sync(store: store) }
            dismiss()
        } catch {
            showError = true
        }
    }
}

/// "Notifications are off for VESS" with a way to Settings.
struct NotificationsDeniedNote: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text("Notifications are off for VESS. You can turn them on in Settings.")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.vessSecondary)
        }
    }
}

extension Supplement {
    /// "1,000 IU · 08:00" or "5 g · no reminder".
    var summary: Text {
        let dose = Text(verbatim: unit.amountText(dosage))
        guard let time = reminderTime,
              let date = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: time.hour, minute: time.minute))
        else { return Text("\(dose) · no reminder") }
        return Text("\(dose) · \(date, format: .dateTime.hour().minute())")
    }
}

extension SupplementUnit {
    /// "1 capsule", "2 tablets", "1,000 IU".
    func amountText(_ amount: Double) -> String {
        if let count = Int(exactly: amount) {
            switch self {
            case .capsule: return String(localized: "\(count) capsule")
            case .tablet: return String(localized: "\(count) tablet")
            default: break
            }
        }
        switch self {
        case .capsule: return String(localized: "\(VESSFormat.quantity(amount)) capsules")
        case .tablet: return String(localized: "\(VESSFormat.quantity(amount)) tablets")
        default: return "\(VESSFormat.quantity(amount)) \(String(localized: abbreviation))"
        }
    }

    var abbreviation: LocalizedStringResource {
        switch self {
        case .milligram: "mg"
        case .microgram: "µg"
        case .gram: "g"
        case .internationalUnit: "IU"
        case .capsule: "capsule"
        case .tablet: "tablet"
        case .milliliter: "ml"
        }
    }
}
