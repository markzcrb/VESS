import SwiftUI

/// A tile in the Add sheet's type carousel (21, 22; Figma AddTypeTile).
///
/// 72 pt, radius 22. The carousel scales tiles away from the centre (down
/// to 0.78, so 56 pt), which keeps the size change continuous while
/// dragging. The fill is the type colour at 20 % (Dark) or 14 % (Light); the
/// icon is the type colour. Neutral types (`hue == nil`) use the plain fill
/// and text colour. The size doesn't scale with Dynamic Type: the name under
/// the carousel does.
struct VESSAddTypeTile: View {
    let systemImage: String
    /// The metric hue, or `nil` for Photo, Habits and Weight.
    let hue: Color?

    @Environment(\.colorScheme) private var colorScheme

    static let size: CGFloat = 72
    private static let radius: CGFloat = 22
    /// Tile fill opacity of the type colour.
    private static let fillOpacityDark = 0.20
    private static let fillOpacityLight = 0.14

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 28, weight: .regular))
            .foregroundStyle(hue ?? VESSColor.text)
            .frame(width: Self.size, height: Self.size)
            .background(fill, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .accessibilityHidden(true)
    }

    private var fill: Color {
        guard let hue else { return VESSColor.fill }
        return hue.opacity(colorScheme == .dark ? Self.fillOpacityDark : Self.fillOpacityLight)
    }
}

#Preview("Tiles") {
    HStack(spacing: VESSSpacing.sm) {
        VESSAddTypeTile(systemImage: "camera", hue: nil).scaleEffect(0.78)
        VESSAddTypeTile(systemImage: "bolt", hue: VESSColor.carbs).scaleEffect(0.78)
        VESSAddTypeTile(systemImage: "fork.knife", hue: VESSColor.calories)
        VESSAddTypeTile(systemImage: "waterbottle", hue: VESSColor.water).scaleEffect(0.78)
    }
    .padding()
    .background(VESSColor.background)
    .preferredColorScheme(.dark)
}
