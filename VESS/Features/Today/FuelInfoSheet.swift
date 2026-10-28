import SwiftUI

/// How the Fuel score is calculated, with today's parts. Opened from the
/// Fuel ring on Today.
struct FuelInfoSheet: View {
    let fuel: FuelScore?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                    Text("How Fuel is calculated")
                        .vessTextStyle(.editorialM)
                        .foregroundStyle(VESSColor.text)
                    Text("Fuel is a summary of what you've logged today against your own targets. It is not a health measurement and says nothing about how healthy you are.")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)

                    VESSRowGroup {
                        part("Energy", weight: 40, detail: "Full marks at 100–105\u{00A0}% of your target, a little less above", value: fuel?.components.energy)
                        part("Protein", weight: 30, detail: "Up to your protein target", value: fuel?.components.protein)
                        part("Hydration", weight: 20, detail: "Up to your water target", value: fuel?.components.hydration)
                        part("Meal regularity", weight: 10, detail: "Each meal near its usual time adds to this part", value: fuel?.components.regularity)
                    }
                    .vessHairlineBottom()

                    VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                        note("Fuel compares what you've logged with your full-day targets, like the rings above it. It builds as you log through the day, so a low number in the morning is expected.")
                        note("It only goes up as you log. The one thing that lowers it is going well past your energy target.")
                        note("Without 3 days of history there's no regularity yet, so the other three parts make up the whole score.")
                        note("Fuel shows \u{2014} until you log something to eat.")
                    }
                }
                // 20 pt from the sheet's edges, the text using the full width.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.vertical, VESSSpacing.screenInset)
            }
            .background(VESSColor.card)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(VESSRadius.sheet)
    }

    private func part(_ title: LocalizedStringResource, weight: Int, detail: LocalizedStringResource, value: Double?) -> some View {
        VESSRow(title: Text("\(Text(title)) · \(weight)\u{00A0}%"), subtitle: Text(detail), subtitleLineLimit: 2) {
            Text(value.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "\u{2014}")
                .vessTextStyle(.numberS)
                .foregroundStyle(VESSColor.text)
        }
        .accessibilityElement(children: .combine)
    }

    private func note(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
