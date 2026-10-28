import SwiftUI

/// FeatureRow (P02): an outline symbol in a raised square, a title and one
/// line of detail.
struct VESSFeatureRow: View {
    let systemImage: String
    let title: Text
    let detail: Text

    @ScaledMetric(relativeTo: .body) private var tile: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: VESSSpacing.md) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(VESSColor.secondaryText)
                .frame(width: tile, height: tile)
                .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous).strokeBorder(VESSColor.divider))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                title
                    .vessTextStyle(.bodyMStrong)
                    .foregroundStyle(VESSColor.text)
                detail
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// PlanCard (P02): a plan's caps name, an optional badge ("−48 %"), the
/// price large and one line under it. The chosen card is outlined in the
/// link accent; the other is a plain raised card.
struct VESSPlanCard: View {
    let title: LocalizedStringResource
    let price: Text
    let detail: Text
    var badge: Text?
    let isSelected: Bool
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text(title)
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                    Spacer(minLength: 0)
                    if let badge {
                        VESSTag(text: badge, tone: .accent)
                    }
                }
                price
                    .vessTextStyle(.displayM)
                    .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                detail
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(VESSSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(VESSColor.card, in: shape)
            .overlay(shape.strokeBorder(isSelected ? VESSColor.accent : VESSColor.divider, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .vessHaptic(.selection, trigger: isSelected)
    }
}

#Preview("Plans") {
    VStack(spacing: VESSSpacing.lg) {
        VESSFeatureRow(systemImage: "bubble.left", title: Text(verbatim: "AI Coach"),
                       detail: Text(verbatim: "15 questions a day, with charts from your own data"))
        HStack(spacing: VESSSpacing.sm) {
            VESSPlanCard(title: "Annual", price: Text(verbatim: "49,99 €"), detail: Text(verbatim: "4,17 € a month, billed yearly"),
                         badge: Text(verbatim: "\u{2212}48\u{00A0}%"), isSelected: true) {}
            VESSPlanCard(title: "Monthly", price: Text(verbatim: "7,99 €"), detail: Text(verbatim: "a month · cancel anytime"), isSelected: false) {}
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding()
    .background(VESSColor.background)
    .preferredColorScheme(.dark)
}
