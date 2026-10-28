import SwiftUI

/// A recipe in a list (R01, R02, R05). `.large` is the featured card with a
/// photo on top; `.row` is a hairline-list row with a square photo. Without
/// a photo, a quiet tile with a symbol. Greyed when the recipe doesn't fit.
struct VESSRecipeCard: View {
    enum Size { case large, row }

    let size: Size
    var photo: Image?
    let kicker: Text
    let title: Text
    let meta: Text
    var badges: [VESSRecipeBadge] = []
    /// Shown greyed, with the reason as a badge ("Has chicken").
    var isDimmed = false

    @ScaledMetric(relativeTo: .body) private var rowPhoto: CGFloat = 72
    @ScaledMetric(relativeTo: .body) private var largePhoto: CGFloat = 180
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            switch size {
            case .large: large
            case .row: row
            }
        }
        .opacity(isDimmed ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The frame first: a filled photo would widen the card.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: min(largePhoto, 260))
                .overlay { photoView }
                .clipped()
            text
                .padding(.horizontal, VESSSpacing.md)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VESSColor.card)
        .clipShape(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.divider))
        // The filled photo is wider than its frame; taps stay inside the card.
        .contentShape(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
    }

    private var row: some View {
        // At accessibility sizes the photo goes above the text.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: VESSSpacing.md))
        return layout {
            Color.clear
                .frame(width: min(rowPhoto, 120), height: min(rowPhoto, 120))
                .overlay { photoView }
                .clipShape(RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous))
            text
            Spacer(minLength: 0)
        }
        .padding(.vertical, VESSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs + 2) {
            kicker
                .vessTextStyle(.labelCapsS)
                .foregroundStyle(VESSColor.tertiaryText)
            title
                .vessTextStyle(.bodyMStrong)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
            meta
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !badges.isEmpty {
                // In a row when they fit, else one under the other; a long
                // tag wraps rather than running past the margin.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VESSSpacing.xs) { tags }
                    VStack(alignment: .leading, spacing: VESSSpacing.xs) { tags }
                }
                .padding(.top, VESSSpacing.xxs)
            }
        }
    }

    private var tags: some View {
        ForEach(badges.indices, id: \.self) { index in
            VESSTag(text: badges[index].text, tone: badges[index].tone)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var photoView: some View {
        if let photo {
            photo
                .resizable()
                .scaledToFill()
                .accessibilityHidden(true)
        } else {
            Rectangle()
                .fill(VESSColor.fill)
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(size == .large ? .title2 : .body)
                        .foregroundStyle(VESSColor.decorative)
                }
                .accessibilityHidden(true)
        }
    }
}

/// A tag on a recipe card: pantry match (neutral or positive), uses
/// use-soon (accent), protein (positive), AI (neutral).
struct VESSRecipeBadge {
    let text: Text
    var tone: VESSTag.Tone = .neutral
}

/// Text tabs with an underline under the selected one ("My recipes ·
/// Discover · AI Chef"), on a hairline.
struct VESSTextTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringResource)]
    var identifier: (Value) -> String = { "\($0)" }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VESSSpacing.xl) { tabItems }
                .frame(maxWidth: .infinity, alignment: .leading)
            // Too wide (large text): the tabs wrap onto more lines, all in
            // view, never cut at an edge.
            VESSChipFlow(spacing: VESSSpacing.lg) { tabItems }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) { VESSHairline() }
        .vessHaptic(.selection, trigger: selection)
    }

    private var tabItems: some View {
        ForEach(options, id: \.value) { option in
            let isSelected = option.value == selection
            Button { selection = option.value } label: {
                VStack(spacing: VESSSpacing.xs) {
                    Text(option.title)
                        .vessTextStyle(isSelected ? .bodyMStrong : .bodyM)
                        .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                        .fixedSize()
                    Rectangle()
                        .fill(isSelected ? VESSColor.text : Color.clear)
                        .frame(height: 2)
                }
                // The underline is as wide as the title.
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .bottom)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("tabs.\(identifier(option.value))")
            .id(option.value)
        }
    }
}
