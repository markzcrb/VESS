import SwiftUI

/// "Add to Dinner ▾" with an optional subtitle. The meal is a menu so it can
/// be changed without leaving the screen.
struct MealPickerHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var meal: MealType

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                Text(title)
                    .vessTextStyle(.detailTitle)
                Menu {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.dayOrder) { meal in
                            Text(meal.title).tag(meal)
                        }
                    }
                } label: {
                    HStack(spacing: VESSSpacing.xxs) {
                        Text(meal.title)
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(VESSColor.accent)
                }
                .accessibilityLabel(Text("Meal: \(Text(meal.title))"))
                .accessibilityIdentifier("mealPicker")
            }
            if let subtitle {
                Text(subtitle)
                    .vessTextStyle(.secondary)
            }
        }
    }
}
