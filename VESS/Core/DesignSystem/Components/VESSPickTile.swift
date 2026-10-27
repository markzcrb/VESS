import SwiftUI

/// PickTile (D01, D03): an outline symbol over its name, 84 pt tall, in a
/// grid of four. The selected tile is raised and outlined in greyscale (a
/// choice, not data). Grows with Dynamic Type; callers drop to fewer
/// columns at larger sizes.
struct VESSPickTile: View {
    let title: Text
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    /// One height for every symbol, so names line up across tiles.
    @ScaledMetric(relativeTo: .title3) private var iconHeight: CGFloat = 26

    static let height: CGFloat = 84

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: VESSSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                    .frame(height: iconHeight)
                    .accessibilityHidden(true)
                title
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.vertical, VESSSpacing.sm)
            .padding(.horizontal, VESSSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .background(isSelected ? VESSColor.borderStrong : VESSColor.fill, in: shape)
            .overlay(shape.strokeBorder(isSelected ? VESSColor.secondaryText : VESSColor.divider, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .vessHaptic(.selection, trigger: isSelected)
    }

    /// Four across; three from the xxLarge text size; two at accessibility sizes.
    static func columns(for size: DynamicTypeSize) -> [GridItem] {
        let count = size.isAccessibilitySize ? 2 : (size > .xLarge ? 3 : 4)
        return Array(repeating: GridItem(.flexible(), spacing: VESSSpacing.xs), count: count)
    }
}

#Preview("Pick tiles") {
    LazyVGrid(columns: VESSPickTile.columns(for: .large), spacing: VESSSpacing.xs) {
        VESSPickTile(title: Text(verbatim: "Water"), systemImage: "drop", isSelected: true) {}
        VESSPickTile(title: Text(verbatim: "Sparkling"), systemImage: "humidity", isSelected: false) {}
        VESSPickTile(title: Text(verbatim: "Coffee"), systemImage: "mug", isSelected: false) {}
        VESSPickTile(title: Text(verbatim: "More"), systemImage: "ellipsis", isSelected: false) {}
    }
    .padding()
    .background(VESSColor.background)
    .preferredColorScheme(.dark)
}
