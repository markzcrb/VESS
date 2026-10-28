import SwiftUI

/// The brand screens' plain background: pearl in Light and graphite in
/// Dark (B01–B03, onboarding), or graphite always (B04). No image.
struct BrandBackground: View {
    var color = VESSColor.launchBackground

    var body: some View {
        color.ignoresSafeArea()
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
