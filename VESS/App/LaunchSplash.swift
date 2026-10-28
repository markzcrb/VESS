import SwiftUI

/// B01: the first frame after the launch screen, the same as it: the plain
/// launch colour with the wordmark at the launch image's place and size
/// (centred in the whole screen, 192 pt wide), so the handoff doesn't
/// jump. B02 puts its wordmark in the same place.
struct LaunchSplash: View {
    /// Width of `LaunchWordmark` in the asset catalog; keep the two equal.
    static let wordmarkWidth: CGFloat = 192

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VESSColor.launchBackground
            .overlay {
                UMEVAWordmark(width: Self.wordmarkWidth)
                    .foregroundStyle(colorScheme == .dark ? VESSColor.brandPearl : VESSColor.brandInk)
            }
            .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

#Preview("B01 Light") {
    LaunchSplash().preferredColorScheme(.light)
}

#Preview("B01 Dark") {
    LaunchSplash().preferredColorScheme(.dark)
}
