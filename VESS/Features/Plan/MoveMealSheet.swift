import SwiftUI

/// A05: move a planned meal to another day or meal of the week, from today on.
struct MoveMealSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let meal: PlannedMeal
    /// Called after a move, so the detail screen can close too.
    var onMoved: () -> Void = {}

    @State private var day: Date
    @State private var mealType: MealType
    @State private var showError = false

    private let calendar = Calendar.current

    init(meal: PlannedMeal, onMoved: @escaping () -> Void = {}) {
        self.meal = meal
        self.onMoved = onMoved
        _day = State(initialValue: meal.day)
        _mealType = State(initialValue: meal.mealType)
    }

    var body: some View {
        let today = calendar.startOfDay(for: AppClock.now)
        let week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfWeek(for: meal.day)) }
        let unchanged = calendar.isDate(day, inSameDayAs: meal.day) && mealType == meal.mealType

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    HStack {
                        Text("Move meal")
                            .vessTextStyle(.titleL)
                            .foregroundStyle(VESSColor.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                    }

                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        Text(meal.name)
                            .vessTextStyle(.editorialL)
                            .foregroundStyle(VESSColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(Text(meal.day, format: .dateTime.weekday(.wide))) · \(Text(meal.mealType.title)) · \(VESSFormat.calories(meal.nutrition.calories))\u{00A0}kcal")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        VESSSectionHeader(title: "Day")
                        VESSDayStrip(
                            days: week,
                            selection: $day,
                            today: today,
                            calendar: calendar,
                            hasEntries: { _ in false },
                            isSelectable: { calendar.startOfDay(for: $0) >= today }
                        )
                    }

                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        VESSSectionHeader(title: "Meal")
                        VESSChipFlow {
                            ForEach(MealType.dayOrder) { option in
                                VESSChip(title: option.title, isSelected: mealType == option) { mealType = option }
                            }
                        }
                    }

                    Group {
                        if unchanged {
                            Text("\(slotName(meal.day, meal.mealType)) is still selected. Your plan hasn't changed.")
                        } else {
                            Text("Moves to \(slotName(day, mealType)).")
                        }
                    }
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    .padding(VESSSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider))
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.xl)
            }
            .background(VESSColor.card)
            .safeAreaInset(edge: .bottom) {
                Button {
                    if unchanged { dismiss() } else { move() }
                } label: {
                    Text(unchanged ? "Keep it here" : "Move to \(slotName(day, mealType))")
                }
                .buttonStyle(.vessPrimary)
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.vertical, VESSSpacing.sm)
                .background(VESSColor.card)
                .accessibilityIdentifier("moveMeal.confirm")
            }
            .toolbar(.hidden, for: .navigationBar)
            .vessErrorAlert(isPresented: $showError, retry: move)
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    /// "Wednesday dinner".
    private func slotName(_ day: Date, _ meal: MealType) -> String {
        "\(day.formatted(.dateTime.weekday(.wide))) \(String(localized: meal.title).lowercased())"
    }

    private func move() {
        var moved = meal
        moved.day = calendar.startOfDay(for: day)
        moved.mealType = mealType
        do {
            try store.save(moved)
            dismiss()
            onMoved()
        } catch {
            showError = true
        }
    }
}
