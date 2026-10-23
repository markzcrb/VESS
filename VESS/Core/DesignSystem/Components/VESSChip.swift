import SwiftUI

/// A selectable capsule for filters, presets and suggestions. Selected is
/// the filled accent capsule; unselected is raised with a hairline. State is
/// carried by luminance and the selected trait, never by hue alone.
struct VESSChip: View {
    let title: LocalizedStringResource
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .vessTextStyle(.bodyS)
                .foregroundStyle(isSelected ? VESSColor.onAccent : VESSColor.text)
                .padding(.horizontal, VESSSpacing.sm + 2)
                .padding(.vertical, VESSSpacing.xs)
                .frame(minHeight: VESSHitTarget.minimum)
                .background {
                    Capsule()
                        .fill(isSelected ? VESSColor.accentFill : VESSColor.fill)
                        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : VESSColor.divider))
                        .padding(.vertical, VESSSpacing.xxs)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .vessHaptic(.selection, trigger: isSelected)
    }
}

/// Lays chips out in rows that wrap to the available width.
struct VESSChipFlow: Layout {
    var spacing: CGFloat = VESSSpacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += (isFirst ? 0 : spacing) + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
