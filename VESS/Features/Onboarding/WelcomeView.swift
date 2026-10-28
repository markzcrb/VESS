import SwiftUI

/// B02, the first screen, shown only before onboarding: the plain launch
/// colour, the wordmark exactly where the launch screen and B01 have it
/// (192 pt, centred in the whole screen), one editorial line, Get started
/// (onboarding) and "I already use UMEVA" (sign in first), and the Terms
/// and Privacy Policy links. Where the content would reach the wordmark
/// (small screens, large text), the wordmark moves to the top and the page
/// scrolls.
struct WelcomeView: View {
    let onStart: () -> Void
    let onSignIn: () -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { screen in
            let wordmarkHeight = LaunchSplash.wordmarkWidth * UMEVAWordmarkShape.viewBox.height / UMEVAWordmarkShape.viewBox.width
            // The launch screen's centre, in this view's (safe-area) space.
            let centreY = (screen.size.height + screen.safeAreaInsets.top + screen.safeAreaInsets.bottom) / 2 - screen.safeAreaInsets.top
            let fits = screen.size.height - contentHeight - (centreY + wordmarkHeight / 2) >= VESSSpacing.xl
            if fits {
                ZStack(alignment: .bottom) {
                    UMEVAWordmark(width: LaunchSplash.wordmarkWidth)
                        .foregroundStyle(VESSColor.text)
                        .position(x: screen.size.width / 2, y: centreY)
                    content
                        .padding(.horizontal, VESSSpacing.screenInset)
                        .padding(.bottom, VESSSpacing.md)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
            } else {
                BrandScreenLayout {
                    UMEVAWordmark(width: UMEVAWordmark.headerWidth)
                        .foregroundStyle(VESSColor.text)
                        .padding(.top, VESSSpacing.xxl)
                } bottom: {
                    content
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
            }
        }
        .background { BrandBackground() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xl) {
            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                Text("Your body, in balance.")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Food, drinks, sleep and recovery in one calm place. Your log stays on this iPhone.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: VESSSpacing.xs) {
                Button("Get started", action: onStart)
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("onboarding.getStarted")
                Button("I already use UMEVA", action: onSignIn)
                    .buttonStyle(.brandText)
                    .accessibilityIdentifier("onboarding.signIn")
            }

            Text(legalCaption)
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
                .tint(VESSColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The sentence with its two links, which come from `LegalLinks`.
    private var legalCaption: AttributedString {
        var caption = AttributedString(localized: "By continuing you agree to the [Terms of Use](umeva:terms) and [Privacy Policy](umeva:privacy).")
        for run in caption.runs {
            guard let link = run.link else { continue }
            caption[run.range].link = link.absoluteString == "umeva:terms" ? LegalLinks.terms : LegalLinks.privacyPolicy
            caption[run.range].underlineStyle = .single
        }
        return caption
    }
}

#Preview("B02 Light") {
    WelcomeView(onStart: {}, onSignIn: {})
        .preferredColorScheme(.light)
}

#Preview("B02 Dark") {
    WelcomeView(onStart: {}, onSignIn: {})
        .preferredColorScheme(.dark)
}
