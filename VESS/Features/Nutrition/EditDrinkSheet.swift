import SwiftUI

/// Edit a logged drink: its amount and time, or delete it. Values scale
/// with the amount (`HydrationLog.edited`); the share toward water stays.
struct EditDrinkSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let log: HydrationLog
    let day: Date

    @State private var volume: Double
    @State private var time: Date
    @State private var showTime = false
    @State private var saved = 0
    @State private var showError = false

    private let calendar = Calendar.current
    private static let step = 10.0
    private static let range = 10.0...2000.0

    init(log: HydrationLog, day: Date) {
        self.log = log
        self.day = day
        _volume = State(initialValue: log.volumeMilliliters)
        _time = State(initialValue: log.loggedAt)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                            Text("Edit drink")
                                .vessTextStyle(.labelCaps)
                                .foregroundStyle(VESSColor.secondaryText)
                            Text(verbatim: log.drinkName)
                                .vessTextStyle(.displayM)
                                .foregroundStyle(VESSColor.text)
                                .accessibilityAddTraits(.isHeader)
                        }
                        Spacer(minLength: VESSSpacing.md)
                        VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                    }

                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        VESSSectionHeader(title: "Amount")
                        HStack(spacing: VESSSpacing.md) {
                            VESSIconButton(systemImage: "minus", label: "Less") { volume = max(Self.range.lowerBound, volume - Self.step) }
                                .disabled(volume <= Self.range.lowerBound)
                            Text("\(VESSFormat.milliliters(volume))\u{00A0}ml")
                                .vessTextStyle(.numberRow)
                                .foregroundStyle(VESSColor.text)
                                .contentTransition(.numericText())
                                .frame(maxWidth: .infinity)
                            VESSIconButton(systemImage: "plus", label: "More") { volume = min(Self.range.upperBound, volume + Self.step) }
                                .disabled(volume >= Self.range.upperBound)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Amount")
                        .accessibilityValue(Text("\(VESSFormat.milliliters(volume))\u{00A0}ml"))
                        .vessHaptic(.selection, trigger: volume)
                    }

                    DrinkTimeRow(time: $time, isExpanded: $showTime, range: DrinkTime.range(on: day, calendar: calendar), identifier: "editDrink.time")

                    Button("Delete this drink", action: delete)
                        .buttonStyle(.vessQuiet)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("editDrink.delete")
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.xl)
            }
            .background(VESSColor.card)
            .vessBottomAction {
                Button("Save", action: save)
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("editDrink.save")
            }
            .toolbar(.hidden, for: .navigationBar)
            .vessHaptic(.success, trigger: saved)
            .vessErrorAlert(isPresented: $showError, retry: save)
        }
        // Full height at accessibility sizes, where half hides the rows.
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    private func save() {
        let before = log
        let updated = log.edited(volumeMilliliters: volume, loggedAt: time)
        do {
            try store.update(updated)
            saved += 1
            undo.show(Text("Updated \(log.drinkName)")) { store in
                try store.update(before)
            }
            dismiss()
        } catch {
            showError = true
        }
    }

    private func delete() {
        let removed = log
        do {
            try store.deleteHydrationLog(id: removed.id)
            undo.show(Text("Deleted \(removed.drinkName)")) { store in
                try store.add(removed)
            }
            dismiss()
        } catch {
            showError = true
        }
    }
}
