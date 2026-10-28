import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The VESS wordmark (option B: an open ring and VESS in caps), from the
/// `VESSWordmark` image set: SVG, Preserve Vector Data, Dark and Light
/// appearances, drawn here as a template in `color`. The ring's track is
/// the same colour at 22 % opacity, so tinting keeps it lighter.
///
/// The launch screen (`UILaunchScreen` in Config/VESS-Info.plist) shows
/// `VESSLaunchWordmark` at its own size, 134 × 30 pt, centred on
/// `VESSBackground`: PNGs at @2x and @3x rendered from these SVGs, because
/// the system's launch screen doesn't draw the SVG. Re-render them when
/// the wordmark changes.
///
/// The text below is only a safety net, should the image ever fail to load.
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
                Text(verbatim: "UMEVA")
                    .font(.system(size: size, weight: .thin))
                    .tracking(size * 0.32)
                    // Trailing tracking would offset the optical center.
                    .padding(.leading, size * 0.32)
            }
        }
        .foregroundStyle(color)
        .accessibilityLabel(Text(verbatim: "UMEVA"))
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
