import SwiftUI

/// Asked once before the first Coach message or photo estimate: what is
/// sent, to whom, and that VESS doesn't keep it (App Store 5.1.2(i)).
/// Allow stores consent for this feature and processor; Not now sends nothing.
struct AIConsentSheet: View {
    let feature: AIFeature
    let onAllow: () -> Void

    @Environment(AIConsentStore.self) private var consent
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    Text(title)
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    VESSRowGroup {
                        fact("What is sent", sent)
                        fact("To whom", Text("\(AIProcessor.displayName), through VESS's server."))
                        fact("Kept?", Text("VESS doesn't store it. \(AIProcessor.company) processes it under its API terms."))
                        fact("What stays here", Text("Your log, profile and history stay on this iPhone."))
                    }
                    .vessHairlineBottom()

                    // At accessibility sizes the buttons end the page, so
                    // what is sent isn't squeezed above a tall pinned area.
                    if dynamicTypeSize.isAccessibilitySize { actions }
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.md)
                .padding(.bottom, VESSSpacing.xl)
            }
            .background(VESSColor.card)
            .scrollEdgeEffectStyle(.soft, for: .top)
            // The footer and buttons sit on the sheet's background below a
            // hairline; the rows scroll above them, never under.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    actions
                        .padding(.horizontal, VESSSpacing.screenInset)
                        .padding(.top, VESSSpacing.md)
                        .padding(.bottom, VESSSpacing.xs)
                        .frame(maxWidth: .infinity)
                        .background(VESSColor.card.ignoresSafeArea(edges: .bottom))
                        .overlay(alignment: .top) { VESSHairline() }
                }
            }
            .vessDetailTitle(navigationTitle)
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }

    /// The note, Allow and Not now.
    private var actions: some View {
        VStack(spacing: VESSSpacing.xs) {
            Group {
                if account.isSignedIn {
                    Text("You can turn this off any time in You › Privacy and data.")
                } else {
                    Text("Needs an account. You can turn this off any time in You › Privacy and data.")
                }
            }
            .vessTextStyle(.bodyS)
            .foregroundStyle(VESSColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, VESSSpacing.xxs)
            Button("Allow") {
                consent.grant(feature)
                dismiss()
                onAllow()
            }
            .buttonStyle(.vessPrimary)
            .accessibilityIdentifier("consent.allow")
            Button("Not now") { dismiss() }
                .buttonStyle(.vessQuiet)
                .frame(minHeight: VESSHitTarget.minimum)
                .accessibilityIdentifier("consent.notNow")
        }
    }

    private var navigationTitle: LocalizedStringResource {
        switch feature {
        case .coach: "Coach"
        case .photo: "Photo estimate"
        case .chef: "AI Chef"
        }
    }

    private var title: LocalizedStringResource {
        switch feature {
        case .coach: "Coach answers with AI."
        case .photo: "Photo estimates use AI."
        case .chef: "AI Chef writes recipes with AI."
        }
    }

    private var sent: Text {
        switch feature {
        case .coach:
            Text("Your question, the conversation so far, and a summary of your recent logs: targets, today's totals, 7-day averages, today's meals, habits, workouts and supplements. Cycle data only if you turn on sharing.")
        case .photo:
            Text("The photo, made smaller and without location or other details from the camera.")
        case .chef:
            Text("Your pantry list (names, and which to use soon), your choices for the recipe, your diet, the ingredients you don't eat, your allergies, and today's protein gap. Nothing else from your log. Nutrition is worked out on this iPhone, not by the AI.")
        }
    }

    private func fact(_ title: LocalizedStringResource, _ detail: Text) -> some View {
        VESSRow(title: Text(title), subtitle: detail, subtitleLineLimit: 6) { EmptyView() } trailing: { EmptyView() }
            .accessibilityElement(children: .combine)
    }
}

extension AIFeature: Identifiable {
    var id: Self { self }
}

extension View {
    /// Presents the consent sheet; `onAllow` runs after Allow.
    func vessAIConsent(_ feature: AIFeature, isPresented: Binding<Bool>, onAllow: @escaping () -> Void) -> some View {
        sheet(isPresented: isPresented) {
            AIConsentSheet(feature: feature, onAllow: onAllow)
        }
    }
}

#Preview("Coach consent") {
    AIConsentSheet(feature: .coach, onAllow: {})
        .environment(AIConsentStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        .environment(AccountStore(config: nil, transport: URLSessionTransport(), store: MemorySessionStore()))
        .preferredColorScheme(.dark)
}
