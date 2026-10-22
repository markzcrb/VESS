import SwiftUI

/// 15: log or edit one day: date, flow, symptoms and a note. Opened from a
/// calendar day, the Note row, or the Add sheet (pushed, without its own
/// close button).
struct CycleDaySheet: View {
    let date: Date

    var body: some View {
        NavigationStack {
            CycleDayForm(date: date, showsClose: true)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }
}

struct CycleDayForm: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let showsClose: Bool
    /// Called after Save or Delete instead of dismissing, when pushed.
    var onDone: (() -> Void)?

    private let originalDate: Date
    @State private var date: Date
    @State private var flow: CycleFlow = .none
    @State private var symptoms: Set<CycleSymptom> = []
    @State private var note = ""
    @State private var existing: CycleDay?
    @State private var showDatePicker = false
    @State private var hasLoaded = false
    @State private var showError = false

    private let calendar = Calendar.current

    init(date: Date, showsClose: Bool, onDone: (() -> Void)? = nil) {
        let day = Calendar.current.startOfDay(for: date)
        originalDate = day
        _date = State(initialValue: day)
        self.showsClose = showsClose
        self.onDone = onDone
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                header
                dateRow
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Flow")
                    CycleFlowChips(flow: $flow)
                }
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    VESSSectionHeader(title: "Symptoms")
                    CycleSymptomChips(symptoms: $symptoms)
                }
                noteField
                Text(CycleCopy.storage)
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // At accessibility sizes only Save is pinned, so the form
                // keeps room to scroll.
                if dynamicTypeSize.isAccessibilitySize, existing != nil {
                    deleteButton
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.md)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(VESSColor.card)
        .vessBottomAction {
            VStack(spacing: VESSSpacing.xs) {
                Button("Save", action: save)
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("cycleDay.save")
                if existing != nil, !dynamicTypeSize.isAccessibilitySize {
                    deleteButton
                }
            }
        }
        .toolbar(showsClose ? .hidden : .automatic, for: .navigationBar)
        .vessKeyboardDoneButton()
        .vessErrorAlert(isPresented: $showError, retry: save)
        .onAppear(perform: load)
    }

    // MARK: Sections

    private var deleteButton: some View {
        Button("Delete this day", action: delete)
            .buttonStyle(.vessQuiet)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("cycleDay.delete")
    }

    /// "CYCLE DAY 1 · EDITING", then "9 October".
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                kicker
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.secondaryText)
                Text(date, format: .dateTime.day().month(.wide))
                    .vessTextStyle(.displayM)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: VESSSpacing.md)
            if showsClose {
                VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var kicker: Text {
        let days = store.cycleDays.filter { $0.id != existing?.id } + (flow.isPeriod ? [draft] : [])
        let cycleDay = CyclePrediction.summary(days, today: date, calendar: calendar).cycleDay
        switch (cycleDay, existing != nil) {
        case (let day?, true): return Text("Cycle day \(day) · Editing")
        case (let day?, false): return Text("Cycle day \(day)")
        case (nil, true): return Text("Editing")
        case (nil, false): return Text("Log a day")
        }
    }

    /// "Date · Thu 9 Oct ›", opening a calendar up to today.
    private var dateRow: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : VESSMotion.selection) { showDatePicker.toggle() }
            } label: {
                VESSListRow(title: Text("Date"), value: Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showDatePicker ? "Hides the calendar" : "Shows a calendar")
            .accessibilityIdentifier("cycleDay.date")
            if showDatePicker {
                DatePicker("Date", selection: dayBinding, in: ...calendar.startOfDay(for: AppClock.now), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(VESSColor.text)
                    .labelsHidden()
            }
        }
        .vessHairlineBottom()
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { date }, set: { date = calendar.startOfDay(for: $0) })
    }

    private var noteField: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous)
        return VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Note")
            TextField("Note", text: $note, prompt: Text("Add a note (optional)").foregroundStyle(VESSColor.tertiaryText), axis: .vertical)
                .lineLimit(3...6)
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
                .padding(VESSSpacing.md)
                .background(VESSColor.fill, in: shape)
                .overlay(shape.strokeBorder(VESSColor.divider))
                .accessibilityIdentifier("cycleDay.note")
        }
    }

    // MARK: Actions

    private var draft: CycleDay {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return CycleDay(id: existing?.id ?? UUID(), day: date, flow: flow, symptoms: symptoms, note: trimmed.isEmpty ? nil : trimmed)
    }

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let day = store.cycleDay(on: originalDate, calendar: calendar) else { return }
        existing = day
        flow = day.flow
        symptoms = day.symptoms
        note = day.note ?? ""
    }

    /// Saves, with Undo restoring both days as they were.
    private func save() {
        let value = draft
        let before = [existing, store.cycleDay(on: date, calendar: calendar)].compactMap { $0 }
        do {
            try store.save(value, calendar: calendar)
            let message = value.isEmpty
                ? Text("Cleared \(value.day, format: .dateTime.day().month(.wide))")
                : Text("Saved \(value.day, format: .dateTime.day().month(.wide))")
            undo.show(message) { [calendar] store in
                try store.deleteCycleDay(id: value.id)
                for day in before { try store.save(day, calendar: calendar) }
            }
            finish()
        } catch {
            showError = true
        }
    }

    private func delete() {
        guard let existing else { return }
        do {
            try store.deleteCycleDay(id: existing.id)
            undo.show(Text("Deleted \(existing.day, format: .dateTime.day().month(.wide))")) { [calendar] store in
                try store.save(existing, calendar: calendar)
            }
            finish()
        } catch {
            showError = true
        }
    }

    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }
}

#if DEBUG
#Preview("Editing · Dark") {
    let store = LocalStore.preview()
    try? MockData.cycleDays(now: AppClock.now, calendar: .current).forEach { try store.save($0, calendar: .current) }
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            CycleDaySheet(date: Calendar.current.date(byAdding: .day, value: -5, to: AppClock.now) ?? AppClock.now)
        }
        .previewEnvironment(store)
        .preferredColorScheme(.dark)
}
#endif
