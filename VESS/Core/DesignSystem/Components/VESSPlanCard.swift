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

/// PlanCard (P02): the plan's caps name with an optional pill ("−48%")
/// beside it, the price, and the period line; a check on the chosen card's
/// corner.
/// Both cards read the same; the chosen one only adds the outline and the
/// check. In a row, give the row `.fixedSize(horizontal: false, vertical:
/// true)` so the cards share the taller one's height.
struct VESSPlanCard: View {
    let title: LocalizedStringResource
    let price: Text
    let detail: Text
    var badge: Text?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                labelRow
                price
                    .vessTextStyle(.displayM)
                    .foregroundStyle(VESSColor.text)
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
            // The check sits on the corner, so the name and pill keep the row.
            .overlay(alignment: .topTrailing) { check.padding(VESSSpacing.xs) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .vessHaptic(.selection, trigger: isSelected)
    }

    /// Name and pill on one baseline; at accessibility sizes the pill goes
    /// under the name, never cut.
    @ViewBuilder
    private var labelRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                name
                pill
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                name
                pill
                Spacer(minLength: 0)
            }
            // Clear of the check on the corner.
            .padding(.trailing, VESSSpacing.md)
        }
    }

    private var name: some View {
        Text(title)
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.text)
            .lineLimit(1)
    }

    /// A card without a pill keeps its height, so both prices line up.
    private var pill: some View {
        VESSTag(text: badge ?? Text(verbatim: "\u{2212}0%"), tone: .accent)
            .lineLimit(1)
            .fixedSize()
            .opacity(badge == nil ? 0 : 1)
            .accessibilityHidden(badge == nil)
    }

    /// On the chosen card's corner.
    private var check: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(VESSColor.accent)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }
}

#Preview("Plans") {
    VStack(spacing: VESSSpacing.lg) {
        VESSFeatureRow(systemImage: "bubble.left", title: Text(verbatim: "AI Coach"),
                       detail: Text(verbatim: "15 questions a day, with charts from your own data"))
        HStack(spacing: VESSSpacing.sm) {
            VESSPlanCard(title: "Annual", price: Text(verbatim: "49,99 €"), detail: Text(verbatim: "a year · 4,17 € a month"),
                         badge: Text(verbatim: "\u{2212}48%"), isSelected: true) {}
            VESSPlanCard(title: "Monthly", price: Text(verbatim: "7,99 €"), detail: Text(verbatim: "a month"), isSelected: false) {}
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding()
    .background(VESSColor.background)
    .preferredColorScheme(.dark)
}
