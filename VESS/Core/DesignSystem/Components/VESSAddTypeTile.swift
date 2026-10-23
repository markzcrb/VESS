import SwiftUI

/// A tile in the Add sheet's type carousel (21, 22; Figma AddTypeTile).
///
/// Selected: 72 pt, radius 22. Otherwise 56 pt, radius 18. The fill is the
/// type colour at 20 % (Dark) or 14 % (Light); the icon is the type colour.
/// Neutral types (`hue == nil`) use the plain fill and text colour. The
/// sizes don't scale with Dynamic Type: the name under the carousel does.
struct VESSAddTypeTile: View {
    let systemImage: String
    /// The metric hue, or `nil` for Photo, Habits and Weight.
    let hue: Color?
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let selectedSize: CGFloat = 72
    static let size: CGFloat = 56
    private static let selectedRadius: CGFloat = 22
    private static let radius: CGFloat = 18
    /// Tile fill opacity of the type colour.
    private static let fillOpacityDark = 0.20
    private static let fillOpacityLight = 0.14

    var body: some View {
        let side = isSelected ? Self.selectedSize : Self.size
        let shape = RoundedRectangle(cornerRadius: isSelected ? Self.selectedRadius : Self.radius, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: isSelected ? 28 : 22, weight: .regular))
            .foregroundStyle(hue ?? VESSColor.text)
            .frame(width: side, height: side)
            .background(fill, in: shape)
            .animation(reduceMotion ? nil : VESSMotion.selection, value: isSelected)
            .accessibilityHidden(true)
    }

    private var fill: Color {
        guard let hue else { return VESSColor.fill }
        return hue.opacity(colorScheme == .dark ? Self.fillOpacityDark : Self.fillOpacityLight)
    }
}

#Preview("Tiles") {
    HStack(spacing: VESSSpacing.sm) {
        VESSAddTypeTile(systemImage: "camera", hue: nil, isSelected: false)
        VESSAddTypeTile(systemImage: "bolt", hue: VESSColor.carbs, isSelected: false)
        VESSAddTypeTile(systemImage: "fork.knife", hue: VESSColor.calories, isSelected: true)
        VESSAddTypeTile(systemImage: "waterbottle", hue: VESSColor.water, isSelected: false)
        VESSAddTypeTile(systemImage: "pills", hue: VESSColor.fat, isSelected: false)
    }
    .padding()
    .background(VESSColor.background)
    .preferredColorScheme(.dark)
}
