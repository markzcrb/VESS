import SwiftUI

/// G01–G02: a drink of any size, pushed from the Add a drink sheet's Custom
/// card. The volume drunk and the share counted toward water are shown and
/// stored separately; the share is an adjustable estimate taken from the
/// drink's default (or the user's own).
struct CustomDrinkView: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss

    let day: Date
    /// Closes the whole sheet (after logging, or with the close button).
    let onClose: () -> Void

    @State private var preset: DrinkPreset
    @State private var volumeText: String
    @State private var contributionPercent: Double = 100
    @State private var saveAsDefault = false
    @State private var time: Date
    @State private var showTime = false
    @State private var showError = false
    @State private var hasLoadedDefaults = false

    private let calendar = Calendar.current
    /// One drink at a time (G02).
    static let volumeRange: ClosedRange<Double> = 1...2000
    private let step: Double = 50

    init(day: Date, preset: DrinkPreset, volume: Double, time: Date, onClose: @escaping () -> Void) {
        self.day = day
        self.onClose = onClose
        _preset = State(initialValue: preset)
        _volumeText = State(initialValue: VESSFormat.milliliters(volume))
        _time = State(initialValue: time)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                header
                amount
                drinkChoice
                contribution
                DrinkTimeRow(time: $time, isExpanded: $showTime, range: DrinkTime.range(on: day, calendar: calendar))
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
            contributionPercent = currentDefault
        }
    }

    // MARK: Sections

    /// Title, the screen's one editorial line, and the day's hydration (G01).
    private var header: some View {
        let hydration = summary
        return VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            HStack(spacing: VESSSpacing.sm) {
                VESSIconButton(systemImage: "chevron.left", label: "Back") { dismiss() }
                    .accessibilityIdentifier("customDrink.back")
                Text("Custom amount")
                    .vessTextStyle(.titleL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                VESSIconButton(systemImage: "xmark", label: "Close") { onClose() }
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
            DrinkChoice(preset: preset) { option in
                preset = option
                contributionPercent = DrinkFacts.contributionPercent(option, profile: store.profile)
                saveAsDefault = false
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

            // Alcohol always counts 0 %, so there's nothing to adjust.
            if preset.type != .alcohol {
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
            }

            if let volume, let typical = DrinkFacts.typicalValues(preset, volume: volume) {
                typical
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        DrinkFacts.contributionPercent(preset, profile: store.profile)
    }

    // MARK: Actions

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
            onClose()
        } catch {
            showError = true
        }
    }
}
