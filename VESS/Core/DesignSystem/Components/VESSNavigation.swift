import SwiftUI

/// Standard scrolling screen container: VESS background, screen insets,
/// consistent section spacing and a native large navigation title.
///
/// Place inside a `NavigationStack`.
struct VESSScreen<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .background(VESSColor.background)
        .navigationTitle(title)
    }
}

/// A section heading with optional trailing detail text or action.
struct VESSSectionHeader: View {
    let title: LocalizedStringResource
    var detail: Text?
    var actionTitle: LocalizedStringResource?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .vessTextStyle(.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: VESSSpacing.md)

            if let actionTitle, let action {
                Button(action: action) { Text(actionTitle) }
                    .font(.subheadline)
                    .foregroundStyle(VESSColor.accent)
                    .frame(minHeight: VESSHitTarget.minimum)
            } else if let detail {
                detail
                    .vessTextStyle(.secondary)
            }
        }
    }
}

/// A compact add action for section headers, such as adding to a meal.
/// The glyph sits on a small soft-green disc inside a full 44 pt hit area.
/// (Pale green disappeared against the dark-mode background.)
struct VESSHeaderAddButton: View {
    let label: LocalizedStringResource
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var discSize: CGFloat = 30

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VESSColor.accent)
                .frame(width: discSize, height: discSize)
                .background(VESSColor.accentSoft, in: Circle())
                .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// A section: header plus content with the standard 12 pt gap.
struct VESSSection<Content: View>: View {
    let header: VESSSectionHeader
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            header
            content
        }
    }
}
