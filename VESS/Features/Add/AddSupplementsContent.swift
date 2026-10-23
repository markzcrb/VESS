import SwiftUI

/// 22: Supplements in the Add sheet. Today's supplements (tap to log, tap a
/// taken one to undo it), then add one: search, category chips, presets
/// with the user's own of the same name first, and Add your own. VESS
/// records the user's choices: no recommended doses, claims or warnings.
struct AddSupplementsContent: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.vessHaptics) private var haptics

    let day: Date

    @State private var query = ""
    @State private var category: SupplementCategory = .vitamins
    @State private var editing: SupplementSheetRequest?
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        let mine = store.supplements
        let today = SupplementRules.today(mine, logs: store.supplementLogs(on: day, calendar: calendar), on: day, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                todaySection(today)
                VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                    VESSSectionHeader(title: "Add a supplement")
                    VESSSearchField(prompt: "Search supplements", text: $query)
                        .accessibilityIdentifier("supplements.search")
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        categoryChips
                        categoryList(mine)
                    } else {
                        results(mine)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.md)
            .padding(.bottom, VESSSpacing.huge)
        }
        .scrollDismissesKeyboard(.immediately)
        .sheet(item: $editing) { request in
            SupplementEditSheet(supplement: request.supplement, preset: request.preset, category: request.category)
        }
        .vessErrorAlert(isPresented: $showError)
    }

    // MARK: Today

    /// "TODAY · 2 OF 4 TAKEN", Edit, and the day's supplements.
    @ViewBuilder
    private func todaySection(_ today: SupplementRules.Today) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if today.dueCount == 0 {
                        Text(isToday ? "Today" : "That day")
                    } else if isToday {
                        Text("Today · \(today.takenCount) of \(today.dueCount) taken")
                    } else {
                        Text("That day · \(today.takenCount) of \(today.dueCount) taken")
                    }
                }
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: VESSSpacing.md)
                if !store.supplements.isEmpty {
                    NavigationLink {
                        SupplementsView()
                    } label: {
                        HStack(spacing: 2) {
                            Text("Edit").vessTextStyle(.bodyS)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VESSColor.tertiaryText)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(VESSColor.secondaryText)
                        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .trailing)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit supplements")
                }
            }
            if today.items.isEmpty {
                Text(store.supplements.isEmpty ? "No supplements yet. Add one below." : "Nothing to take today.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: VESSSize.rowHeight, alignment: .leading)
            } else {
                VESSRowGroup {
                    ForEach(today.items, id: \.supplement.id) { item in
                        todayRow(item)
                    }
                }
                .vessHairlineBottom()
            }
        }
    }

    private func todayRow(_ item: SupplementRules.Item) -> some View {
        Button {
            if item.takenAt == nil { log(item.supplement) } else { unlog(item.supplement) }
        } label: {
            VESSListRow(
                systemImage: item.takenAt == nil ? "clock" : "checkmark",
                title: Text(verbatim: item.supplement.name),
                subtitle: item.supplement.addSubtitle(calendar: calendar),
                value: item.takenAt.map { Text("Taken \($0, format: .dateTime.hour().minute())") } ?? Text("Tap to log"),
                showsChevron: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(item.takenAt == nil ? Text("Logs it as taken now") : Text("Marks it as not taken"))
        .accessibilityIdentifier("supplements.today.\(item.supplement.name)")
    }

    private var isToday: Bool { calendar.isDate(day, inSameDayAs: AppClock.now) }

    /// Taken now (or at this time of the chosen day), with Undo.
    private func log(_ supplement: Supplement) {
        guard let profile = store.profile else { return }
        let now = AppClock.now
        let takenAt = isToday ? now : (calendar.date(bySettingHour: calendar.component(.hour, from: now), minute: calendar.component(.minute, from: now), second: 0, of: day) ?? day)
        let entry = SupplementLog(id: UUID(), userID: profile.id, supplementID: supplement.id, takenAt: takenAt, dosage: supplement.dosage, unit: supplement.unit)
        do {
            try store.add(entry)
            undo.show(Text("Logged \(supplement.name)")) { store in
                try store.deleteSupplementLog(id: entry.id)
            }
        } catch {
            showError = true
        }
    }

    private func unlog(_ supplement: Supplement) {
        do {
            for entry in store.supplementLogs(on: day, calendar: calendar) where entry.supplementID == supplement.id {
                try store.deleteSupplementLog(id: entry.id)
            }
            haptics.play(.warning)
        } catch {
            showError = true
        }
    }

    // MARK: Add

    private var categoryChips: some View {
        VESSBleedingRow {
            HStack(spacing: VESSSpacing.xs) {
                ForEach(SupplementCategory.allCases, id: \.self) { option in
                    VESSChip(title: option.title, isSelected: category == option) { category = option }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func categoryList(_ mine: [Supplement]) -> some View {
        let presets = SupplementRules.presets(in: category, mine: mine)
        let own = SupplementRules.ownOnly(in: category, mine: mine)
        return VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: category.title)
            VESSRowGroup {
                ForEach(presets, id: \.preset.name) { item in
                    presetRow(item.preset, existing: item.existing)
                }
                ForEach(own) { supplement in
                    mineRow(supplement)
                }
                addYourOwnRow
            }
            .vessHairlineBottom()
        }
    }

    @ViewBuilder
    private func results(_ mine: [Supplement]) -> some View {
        let found = SupplementRules.search(query, mine: mine)
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            VESSSectionHeader(title: "Results")
            VESSRowGroup {
                ForEach(found.mine) { supplement in
                    mineRow(supplement)
                }
                ForEach(found.presets, id: \.name) { preset in
                    presetRow(preset, existing: nil)
                }
                addYourOwnRow
            }
            .vessHairlineBottom()
        }
    }

    /// "Vitamin D3 · Recent · 2,000 IU" opens the user's own; otherwise
    /// "Vitamins · you set the dose".
    private func presetRow(_ preset: SupplementRules.Preset, existing: Supplement?) -> some View {
        Button {
            editing = SupplementSheetRequest(supplement: existing, preset: preset, category: preset.category)
        } label: {
            VESSListRow(
                systemImage: "plus",
                title: Text(verbatim: preset.name),
                subtitle: existing.map { Text("Recent · \($0.unit.amountText($0.dosage))") }
                    ?? Text("\(Text(preset.category.title)) · you set the dose")
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("supplements.preset.\(preset.name)")
    }

    private func mineRow(_ supplement: Supplement) -> some View {
        Button {
            editing = SupplementSheetRequest(supplement: supplement, preset: nil, category: supplement.category)
        } label: {
            VESSListRow(
                systemImage: "plus",
                title: Text(verbatim: supplement.name),
                subtitle: Text("Recent · \(supplement.unit.amountText(supplement.dosage))")
            )
        }
        .buttonStyle(.plain)
    }

    private var addYourOwnRow: some View {
        Button {
            editing = SupplementSheetRequest(supplement: nil, preset: nil, category: category)
        } label: {
            VESSListRow(systemImage: "plus", title: Text("Add your own"), subtitle: Text("Name, dose and unit"))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("supplements.addOwn")
    }
}

private struct SupplementSheetRequest: Identifiable {
    let id = UUID()
    let supplement: Supplement?
    let preset: SupplementRules.Preset?
    let category: SupplementCategory?
}

extension Supplement {
    /// "2,000 IU · Morning", "5 g · Daily", "1 capsule · Mon · Wed · Fri".
    func addSubtitle(calendar: Calendar) -> Text {
        let dose = Text(verbatim: unit.amountText(dosage))
        if let timeOfDay, timeOfDay != .custom {
            return Text("\(dose) · \(Text(timeOfDay.title))")
        }
        if timeOfDay == .custom, let time = reminderTime,
           let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: time.hour, minute: time.minute)) {
            return Text("\(dose) · \(date, format: .dateTime.hour().minute())")
        }
        switch schedule {
        case .daily: return Text("\(dose) · Daily")
        case .asNeeded: return Text("\(dose) · As needed")
        case .weekdays(let days):
            let all: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            let symbols = calendar.shortStandaloneWeekdaySymbols
            let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }.filter { days.contains(all[$0]) }
            return Text("\(dose) · \(Text(verbatim: ordered.map { symbols[$0] }.joined(separator: " · ")))")
        }
    }
}
