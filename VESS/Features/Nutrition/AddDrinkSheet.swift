import SwiftUI

/// G01–G02: log a drink. The volume drunk and the share counted toward
/// hydration are shown and stored separately; the share is an adjustable
/// estimate taken from the drink's default (or the user's own).
struct AddDrinkSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss

    let day: Date
    @State private var preset: DrinkPreset = .water
    @State private var volumeText = ""
    @State private var contributionPercent: Double = 100
    @State private var saveAsDefault = false
    @State private var time = AppClock.now
    @State private var showError = false
    @State private var hasLoadedDefaults = false

    private let calendar = Calendar.current
    /// One drink at a time (G02).
    static let volumeRange: ClosedRange<Double> = 1...2000
    private let step: Double = 50

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    header
                    amount
                    drinkChoice
                    contribution
                    timeRow
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(VESSColor.card)
            .safeAreaInset(edge: .bottom) { addButton }
            .toolbar(.hidden, for: .navigationBar)
            .vessErrorAlert(isPresented: $showError, retry: add)
            .vessKeyboardDoneButton()
            .onAppear {
                guard !hasLoadedDefaults else { return }
                hasLoadedDefaults = true
                time = defaultTime
                select(.water)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    // MARK: Sections

    /// Title, the screen's one editorial line, and today's hydration.
    private var header: some View {
        let hydration = summary
        return VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            HStack {
                Text("Add a drink")
                    .vessTextStyle(.titleL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
            }
            if let hydration {
                Text(hydration.isTargetReached ? "Water target reached." : "A little more water.")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                Text("Hydration · \(VESSFormat.liters(fromMilliliters: hydration.consumedMilliliters)) of \(VESSFormat.liters(fromMilliliters: hydration.targetMilliliters)) L \(Text(isToday ? "today" : "that day"))")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
    }

    /// "− 300 ml +", typed or stepped by 50 ml. Out of range says so (G02).
    private var amount: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Amount")
            HStack(spacing: VESSSpacing.md) {
                VESSIconButton(systemImage: "minus", label: "Less") { stepVolume(by: -1) }
                    .disabled((enteredVolume ?? 0) <= step)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xxs) {
                    TextField(text: $volumeText) { EmptyView() }
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .vessTextStyle(.displayM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize()
                        .accessibilityLabel("Amount in milliliters")
                        .accessibilityIdentifier("addDrink.volume")
                    Text("ml")
                        .vessTextStyle(.numberRow)
                        .foregroundStyle(VESSColor.text)
                }
                Spacer(minLength: 0)
                VESSIconButton(systemImage: "plus", label: "More") { stepVolume(by: 1) }
                    .disabled((enteredVolume ?? 0) >= Self.volumeRange.upperBound)
            }
            if isOutOfRange {
                Text("Enter between 1 and \(VESSFormat.milliliters(Self.volumeRange.upperBound)) ml")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.warningText)
                    .accessibilityIdentifier("addDrink.error")
            }
        }
    }

    private var drinkChoice: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            VESSSectionHeader(title: "Drink")
            VESSChipFlow {
                ForEach(DrinkPreset.allCases, id: \.self) { option in
                    VESSChip(title: option.title, isSelected: preset == option) {
                        select(option)
                    }
                }
            }
        }
    }

    /// "Counts as 300 ml toward water.", the share as an adjustable
    /// estimate, and typical kcal and caffeine.
    private var contribution: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            Group {
                if isOutOfRange {
                    Text("Up to \(VESSFormat.milliliters(Self.volumeRange.upperBound)) ml at a time.")
                } else if let volume {
                    Text("Counts as \(VESSFormat.milliliters(volume * contributionPercent / 100)) ml toward water.")
                }
            }
            .vessTextStyle(.bodyM)
            .foregroundStyle(VESSColor.secondaryText)
            .padding(VESSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                    .strokeBorder(VESSColor.divider)
            )

            HStack {
                Text("\(Text(preset.title)) counts at \(Text(contributionPercent / 100, format: .percent.precision(.fractionLength(0)))). An estimate you can change.")
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: VESSSpacing.sm)
                Stepper("Hydration contribution", value: $contributionPercent, in: 0...100, step: 5)
                    .labelsHidden()
                    .accessibilityValue(Text(contributionPercent / 100, format: .percent.precision(.fractionLength(0))))
            }

            if contributionPercent != currentDefault {
                Toggle(isOn: $saveAsDefault) {
                    Text("Use this for \(Text(preset.title)) from now on")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.text)
                }
                .toggleStyle(.vess)
            }

            if let typical = typicalValuesText {
                Text(typical)
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
            }
        }
    }

    private var timeRow: some View {
        HStack {
            Text("Time")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
            Spacer()
            DatePicker("Time", selection: $time, in: timeRange, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .frame(minHeight: VESSSize.rowHeight)
        .vessHairlineBottom()
    }

    private var addButton: some View {
        Button(action: add) {
            if let volume {
                Text("Add \(VESSFormat.milliliters(volume)) ml")
            } else {
                Text("Add")
            }
        }
        .buttonStyle(.vessPrimary)
        .disabled(volume == nil)
        .padding(.horizontal, VESSSpacing.screenInset)
        .padding(.vertical, VESSSpacing.sm)
        .background(VESSColor.card)
        .accessibilityIdentifier("addDrink.submit")
    }

    // MARK: Values

    private var isToday: Bool {
        calendar.isDate(day, inSameDayAs: AppClock.now)
    }

    private var summary: HydrationProgress? {
        guard let profile = store.profile else { return nil }
        return HydrationProgress(
            logs: store.hydrationLogs(on: day, calendar: calendar),
            targetMilliliters: profile.waterTargetMilliliters,
            day: day,
            calendar: calendar
        )
    }

    private var enteredVolume: Double? {
        VESSFormat.number(from: volumeText)
    }

    /// The volume to log, or `nil` when empty or out of range.
    private var volume: Double? {
        guard let value = enteredVolume, Self.volumeRange.contains(value) else { return nil }
        return value
    }

    private var isOutOfRange: Bool {
        guard let value = enteredVolume else { return false }
        return !Self.volumeRange.contains(value)
    }

    private var currentDefault: Double {
        store.profile?.hydrationContributionPercent(for: preset) ?? preset.defaultHydrationContributionPercent
    }

    private var typicalValuesText: String? {
        guard let volume else { return nil }
        let drink = preset.drink(name: "")
        let calories = drink.caloriesPer100Milliliters * volume / 100
        let caffeine = drink.caffeineMilligramsPer100Milliliters * volume / 100
        guard calories > 0 || caffeine > 0 else { return nil }
        return String(localized: "Typical values: about \(VESSFormat.calories(calories)) kcal and \(VESSFormat.grams(caffeine)) mg caffeine.")
    }

    /// Now for today; noon for a past day.
    private var defaultTime: Date {
        if isToday { return AppClock.now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    /// The chosen day, up to now when it's today.
    private var timeRange: ClosedRange<Date> {
        let start = calendar.startOfDay(for: day)
        let end = isToday ? AppClock.now : (calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-60) ?? day)
        return start...max(start, end)
    }

    // MARK: Actions

    private func select(_ option: DrinkPreset) {
        preset = option
        volumeText = VESSFormat.milliliters(option.defaultVolumeMilliliters)
        contributionPercent = store.profile?.hydrationContributionPercent(for: option)
            ?? option.defaultHydrationContributionPercent
        saveAsDefault = false
    }

    private func stepVolume(by direction: Double) {
        let current = enteredVolume ?? 0
        let next = ((current / step).rounded() + direction) * step
        volumeText = VESSFormat.milliliters(min(max(next, step), Self.volumeRange.upperBound))
    }

    private func add() {
        guard var profile = store.profile, let volume else { return }
        let drink = preset.drink(name: String(localized: preset.title), hydrationContributionPercent: contributionPercent)
        let log = drink.log(userID: profile.id, volumeMilliliters: volume, at: time)
        do {
            try store.add(log)
            undo.show(Text("Added \(VESSFormat.milliliters(volume)) ml of \(drink.name)")) { store in
                try store.deleteHydrationLog(id: log.id)
            }
            if saveAsDefault && contributionPercent != currentDefault {
                var overrides = profile.hydrationContributionOverrides ?? [:]
                overrides[preset] = contributionPercent
                profile.hydrationContributionOverrides = overrides
                try store.saveProfile(profile)
            }
            dismiss()
        } catch {
            showError = true
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddDrinkSheet(day: AppClock.now)
                .environment(LocalStore.preview())
        }
}
