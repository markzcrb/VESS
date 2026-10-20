import SwiftUI

/// Log a drink. The volume drunk and the share counted toward hydration are
/// shown and stored separately; the share is an adjustable estimate.
struct AddDrinkSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let day: Date
    @State private var preset: DrinkPreset = .water
    @State private var volumeText = ""
    @State private var contributionPercent: Double = 100
    @State private var saveAsDefault = false
    @State private var showError = false
    @State private var hasLoadedDefaults = false

    private let calendar = Calendar.current
    private let volumePresets: [Double] = [150, 250, 330, 500]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    Text("Add a drink")
                        .vessTextStyle(.detailTitle)

                    VESSChipFlow {
                        ForEach(DrinkPreset.allCases, id: \.self) { option in
                            VESSChip(title: option.title, isSelected: preset == option) {
                                select(option)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                        VESSTextField("Volume", text: $volumeText, unit: "ml")
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("addDrink.volume")
                        VESSChipFlow {
                            ForEach(volumePresets, id: \.self) { amount in
                                VESSChip(
                                    title: "\(VESSFormat.milliliters(amount)) ml",
                                    isSelected: volume == amount
                                ) {
                                    volumeText = VESSFormat.milliliters(amount)
                                }
                            }
                        }
                    }

                    contributionSection

                    if let typical = typicalValuesText {
                        Text(typical)
                            .vessTextStyle(.label)
                    }
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.bottom, VESSSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(VESSColor.card)
            .safeAreaInset(edge: .bottom) {
                Button(action: add) {
                    Text("Add \(VESSFormat.milliliters(volume ?? 0)) ml")
                }
                .buttonStyle(.vessPrimary)
                .disabled(volume == nil)
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.vertical, VESSSpacing.sm)
                .background(VESSColor.card)
                .accessibilityIdentifier("addDrink.submit")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .vessErrorAlert(isPresented: $showError, retry: add)
            .vessKeyboardDoneButton()
            .onAppear {
                guard !hasLoadedDefaults else { return }
                hasLoadedDefaults = true
                select(.water)
            }
        }
        .presentationDetents([.large])
    }

    private var contributionSection: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text("Counts toward hydration")
                .vessTextStyle(.label)

            HStack {
                Text(contributionPercent / 100, format: .percent.precision(.fractionLength(0)))
                    .vessTextStyle(.metric)
                Spacer()
                Stepper("Hydration contribution", value: $contributionPercent, in: 0...100, step: 5)
                    .labelsHidden()
                    .accessibilityValue(Text(contributionPercent / 100, format: .percent.precision(.fractionLength(0))))
            }

            if let volume {
                Text("\(VESSFormat.milliliters(volume)) ml drunk · counts as \(VESSFormat.milliliters(volume * contributionPercent / 100)) ml")
                    .vessTextStyle(.secondary)
            }

            if contributionPercent != currentDefault {
                Toggle(isOn: $saveAsDefault) {
                    Text("Use this for \(Text(preset.title)) from now on")
                        .font(.subheadline)
                        .foregroundStyle(VESSColor.text)
                }
                .tint(VESSColor.accent)
            }

            Text("An estimate you can adjust, not a measurement.")
                .vessTextStyle(.label)
        }
    }

    // MARK: Values

    private var volume: Double? {
        guard let value = VESSFormat.number(from: volumeText), (1...3000).contains(value) else { return nil }
        return value
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

    // MARK: Actions

    private func select(_ option: DrinkPreset) {
        preset = option
        volumeText = VESSFormat.milliliters(option.defaultVolumeMilliliters)
        contributionPercent = store.profile?.hydrationContributionPercent(for: option)
            ?? option.defaultHydrationContributionPercent
        saveAsDefault = false
    }

    private var logTime: Date {
        if calendar.isDate(day, inSameDayAs: AppClock.now) { return AppClock.now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private func add() {
        guard var profile = store.profile, let volume else { return }
        let drink = preset.drink(name: String(localized: preset.title), hydrationContributionPercent: contributionPercent)
        let log = drink.log(userID: profile.id, volumeMilliliters: volume, at: logTime)
        do {
            try store.add(log)
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
                .environment(LocalStore.preview(.profileOnly))
        }
}
