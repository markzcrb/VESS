import SwiftUI

/// B01: the first frame after the launch screen. Silk full-bleed with the
/// wordmark at the launch image's place and size (centred in the whole
/// screen, 192 pt wide), so the handoff doesn't jump. `AppRootView` fades it
/// out as soon as the store is ready.
struct LaunchSplash: View {
    /// Width of `LaunchWordmark` in the asset catalog; keep the two equal.
    static let wordmarkWidth: CGFloat = 192

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The silk fills the screen as an overlay so its size never moves the
        // wordmark off the screen's centre.
        VESSColor.launchBackground
            .overlay {
                Image(VESSBrandAssets.silk)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
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
