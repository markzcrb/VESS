import SwiftUI

/// The first screen. Typographic by design: no photography is required.
/// A licensed image named `WelcomeHero` in the asset catalog appears above
/// the wordmark automatically.
struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if VESSBrandAssets.isAvailable(VESSBrandAssets.welcomeHero) {
                Image(VESSBrandAssets.welcomeHero)
                    .resizable()
                    .scaledToFill()
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
                    .accessibilityHidden(true)
                    .padding(.top, VESSSpacing.lg)
            }

            Spacer(minLength: VESSSpacing.huge)

            VStack(spacing: VESSSpacing.lg) {
                VESSWordmark()
                Text("Your body. Better understood.")
                    .font(.title3)
                    .foregroundStyle(VESSColor.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: VESSSpacing.huge)

            VStack(spacing: VESSSpacing.lg) {
                // A single thin Vessel Line as the only ornament.
                Capsule()
                    .fill(VESSColor.accent)
                    .frame(width: 32, height: 2)
                    .accessibilityHidden(true)

                Text("What you eat and drink, how you move, and what's at home, understood together.")
                    .font(.body)
                    .foregroundStyle(VESSColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Get started") { onStart() }
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("onboarding.getStarted")

                Text("Your data stays on this iPhone.")
                    .vessTextStyle(.label)
            }
        }
        .padding(.horizontal, VESSSpacing.screenInset + VESSSpacing.xs)
        .padding(.bottom, VESSSpacing.md)
    }
}

#Preview {
    WelcomeView {}
        .background(VESSColor.background)
}
