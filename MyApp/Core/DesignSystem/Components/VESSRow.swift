import SwiftUI

/// A card of rows separated by hairlines. The card itself is the only
/// surface: rows inside never get their own background (no nested cards).
struct VESSRowGroup<Content: View>: View {
    /// Leading inset of the separators, so they align with row text.
    var dividerInset: CGFloat = VESSSpacing.lg
    @ViewBuilder let content: Content

    var body: some View {
        VESSCard(padding: 0) {
            Group(subviews: content) { subviews in
                VStack(spacing: 0) {
                    ForEach(subviews) { subview in
                        subview
                        if subview.id != subviews.last?.id {
                            Rectangle()
                                .fill(VESSColor.divider)
                                .frame(height: 0.5)
                                .padding(.leading, dividerInset)
                        }
                    }
                }
            }
        }
    }
}

/// A standard row: optional leading view, title and subtitle, optional trailing view.
struct VESSRow<Leading: View, Trailing: View>: View {
    let title: Text
    var subtitle: Text?
    var titleStyle: VESSTextStyle = .body
    var subtitleLineLimit = 1
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the trailing value moves below the text,
        // so titles keep the full width instead of breaking mid-word.
        let isStacked = dynamicTypeSize.isAccessibilitySize

        HStack(spacing: VESSSpacing.sm) {
            leading

            VStack(alignment: .leading, spacing: VESSSpacing.xxs / 2) {
                title
                    .vessTextStyle(titleStyle)
                    .lineLimit(isStacked ? nil : 2)
                if let subtitle {
                    subtitle
                        .vessTextStyle(.secondary)
                        .lineLimit(isStacked ? nil : subtitleLineLimit)
                }
                if isStacked {
                    trailing
                        .padding(.top, VESSSpacing.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !isStacked {
                trailing
            }
        }
        .padding(.horizontal, VESSSpacing.lg)
        .padding(.vertical, VESSSpacing.sm)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension VESSRow where Leading == EmptyView {
    init(
        title: Text,
        subtitle: Text? = nil,
        titleStyle: VESSTextStyle = .body,
        subtitleLineLimit: Int = 1,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            titleStyle: titleStyle,
            subtitleLineLimit: subtitleLineLimit,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}

/// A square row thumbnail: the user's photo in later phases, otherwise a
/// quiet tile with a symbol. Never stock imagery.
struct VESSThumbnail: View {
    let systemImage: String
    var isAction = false

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 48

    var body: some View {
        RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous)
            .fill(isAction ? VESSColor.accentPale : VESSColor.fill)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.body.weight(isAction ? .medium : .regular))
                    .foregroundStyle(isAction ? VESSColor.accent : VESSColor.secondaryText)
            }
            .accessibilityHidden(true)
    }
}
