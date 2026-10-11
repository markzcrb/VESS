import SwiftUI

/// A raised content surface. Use cards to group related content, not to
/// frame every element: plain sections on the background often read better.
struct VESSCard<Content: View>: View {
    var padding: CGFloat = VESSSpacing.lg
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)

        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(VESSColor.card, in: shape)
            .overlay(shape.strokeBorder(VESSColor.divider, lineWidth: 0.5))
            .vessElevation()
    }
}
