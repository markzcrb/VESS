import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The VESS wordmark.
///
/// TEMPORARY PLACEHOLDER: the approved wordmark and V mark exist only as
/// mockups. Until the vector files arrive, this renders a plain text
/// "VESS" in thin, widely tracked SF Pro. It is not the final logo.
///
/// To install the real asset, add an image set named `VESSWordmark`
/// (see `VESSBrandAssets`)
/// (PDF or SVG, "Preserve Vector Data", rendering mode Template) to
/// `Assets.xcassets`. This view picks it up automatically; no screen changes.
struct VESSWordmark: View {
    /// Cap height-ish size of the wordmark in points, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40
    var color: Color = VESSColor.text

    var body: some View {
        Group {
            if VESSBrandAssets.isAvailable(VESSBrandAssets.wordmark) {
                Image("VESSWordmark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(height: size)
            } else {
                Text(verbatim: "VESS")
                    .font(.system(size: size, weight: .thin))
                    .tracking(size * 0.32)
                    // Trailing tracking would offset the optical center.
                    .padding(.leading, size * 0.32)
            }
        }
        .foregroundStyle(color)
        .accessibilityLabel(Text(verbatim: "VESS"))
    }
}

/// Names of replaceable brand images. Screens check availability so final
/// assets can be dropped into the asset catalog without code changes.
enum VESSBrandAssets {
    /// The wordmark (vector, template rendering).
    static let wordmark = "VESSWordmark"
    /// Optional welcome-screen image. Only licensed imagery.
    static let welcomeHero = "WelcomeHero"

    static func isAvailable(_ name: String) -> Bool {
        #if canImport(UIKit)
        UIImage(named: name) != nil
        #else
        false
        #endif
    }
}
