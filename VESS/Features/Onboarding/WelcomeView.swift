import SwiftUI

/// B02, the first screen, shown only before onboarding: silk, the
/// wordmark, one editorial line, Get started (onboarding) and "I already
/// use UMEVA" (sign in first), and the Terms and Privacy Policy links.
struct WelcomeView: View {
    let onStart: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        BrandScreenLayout {
            UMEVAWordmark(width: UMEVAWordmark.headerWidth)
                .foregroundStyle(VESSColor.text)
                .padding(.top, VESSSpacing.xxl)
        } bottom: {
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
        .background { BrandSilkBackground() }
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
