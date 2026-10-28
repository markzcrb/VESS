import SwiftUI

/// The brand screens' background (B02–B04): silk on the top part of the
/// screen, fading into the plain base colour where the text sits.
struct BrandSilkBackground: View {
    /// `VESSBrandAssets.silk` (pearl / graphite by appearance) or
    /// `.silkGraphite` (UMEVA+, always graphite).
    var image = VESSBrandAssets.silk
    var base = VESSColor.launchBackground
    /// The part of the screen's height the silk covers before it has faded.
    var coverage: CGFloat = 0.62

    var body: some View {
        base
            .overlay(alignment: .top) {
                Image(decorative: image)
                    .resizable()
                    .scaledToFill()
                    .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                        axis == .vertical ? length * coverage : length
                    }
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black, location: 0.55),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// Text-only action under a brand screen's primary button ("I already use
/// UMEVA", "Done"): text colour, 44 pt tall, full width.
struct BrandTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vessTextStyle(.bodyMStrong)
            .foregroundStyle(VESSColor.text)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == BrandTextButtonStyle {
    static var brandText: BrandTextButtonStyle { BrandTextButtonStyle() }
}

/// A brand screen's layout: fills the screen as designed, and scrolls at
/// large text sizes instead of truncating, so the buttons stay reachable.
struct BrandScreenLayout<Top: View, Bottom: View>: View {
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    top
                    Spacer(minLength: VESSSpacing.xl)
                    bottom
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.bottom, VESSSpacing.md)
                .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
