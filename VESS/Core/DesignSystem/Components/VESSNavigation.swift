import SwiftUI

/// Standard scrolling screen container: VESS background, screen insets,
/// consistent section spacing and a native large navigation title.
///
/// Place inside a `NavigationStack`.
struct VESSScreen<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .background(VESSColor.background)
        .navigationTitle(title)
    }
}

/// A section heading: TRACKED CAPS title, then an optional trailing
/// detail or action ("Diary ›").
struct VESSSectionHeader: View {
    let title: LocalizedStringResource
    var detail: Text?
    var actionTitle: LocalizedStringResource?
    var action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the action goes under the title, so neither
        // breaks mid-word.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))

        layout {
            Text(title)
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
                .accessibilityAddTraits(.isHeader)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: VESSSpacing.md)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                            .vessTextStyle(.bodyS)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VESSColor.tertiaryText)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(VESSColor.secondaryText)
                    .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if let detail {
                detail
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
            }
        }
    }
}

/// A compact add action for section headers, such as adding to a meal.
/// The glyph sits on a small raised disc inside a full 44 pt hit area.
struct VESSHeaderAddButton: View {
    let label: LocalizedStringResource
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var discSize: CGFloat = 30

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VESSColor.text)
                .frame(width: discSize, height: discSize)
                .background(VESSColor.fill, in: Circle())
                .overlay(Circle().strokeBorder(VESSColor.divider))
                .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// A section: header plus content with the standard 12 pt gap.
struct VESSSection<Content: View>: View {
    let header: VESSSectionHeader
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            header
            content
        }
    }
}

extension View {
    /// Detail-screen navigation: a centred TRACKED CAPS title with an optional
    /// caption below it, and a transparent bar.
    func vessDetailTitle(_ title: LocalizedStringResource, subtitle: Text? = nil) -> some View {
        navigationBarTitleDisplayMode(.inline)
            .navigationTitle(Text(title))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(title)
                            .vessTextStyle(.labelCaps)
                            .foregroundStyle(VESSColor.text)
                        subtitle?
                            .vessTextStyle(.caption)
                            .foregroundStyle(VESSColor.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
    }

    /// `vessDetailTitle` for a screen shown on its own; nothing when it's
    /// embedded in the Add sheet (21), whose nav bar keeps "ADD" and the X.
    @ViewBuilder
    func vessStandaloneTitle(_ title: LocalizedStringResource, embedded: Bool, hidesTabBar: Bool = true) -> some View {
        if embedded {
            self
        } else if hidesTabBar {
            vessDetailTitle(title).toolbar(.hidden, for: .tabBar)
        } else {
            vessDetailTitle(title)
        }
    }

    /// Tab roots: content scrolling under the glass tab bar fades into the
    /// canvas, so the bar's mirrored lensing never makes labels hard to read.
    func vessTabBarFade() -> some View {
        scrollEdgeEffectStyle(.soft, for: .bottom)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [VESSColor.background.opacity(0), VESSColor.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: VESSSize.tabBarFade)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    /// The screen background: the canvas, with a metric-tinted atmosphere
    /// fading out over the top 440 pt. `nil` draws the plain canvas.
    ///
    /// Content is clipped at the top of the safe area, so text scrolled up
    /// never shows through behind the navigation bar's buttons; it still
    /// runs under the tab bar, and the atmosphere runs under both bars.
    /// Pass `clipsUnderBar: false` to let content run under the bar and use
    /// the system's soft scroll-edge effect instead of a hard edge.
    ///
    /// Inside the Add sheet it draws nothing: the sheet has one background.
    func vessScreenBackground(_ metric: VESSMetricKind? = .fuel, clipsUnderBar: Bool = true) -> some View {
        modifier(VESSScreenBackground(metric: metric, clipsUnderBar: clipsUnderBar))
    }

    /// Content stops at the bottom of the nav bar and fades in over 24 pt
    /// there, so nothing (even at AX5) sits under the title or its buttons.
    func vessFadeUnderNavBar() -> some View {
        mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: VESSSpacing.xl)
                Rectangle()
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The gap above a screen's first content: `standalone` on its own, the
    /// same 24 pt under the carousel's hairline for every Add sheet type.
    func vessContentTop(_ standalone: CGFloat) -> some View {
        modifier(VESSContentTop(standalone: standalone))
    }
}

extension EnvironmentValues {
    /// True for content shown inside the Add sheet (21), which brings its own
    /// background, title and top gap, so the content draws none of them.
    @Entry var vessInAddSheet = false
}

private struct VESSScreenBackground: ViewModifier {
    let metric: VESSMetricKind?
    let clipsUnderBar: Bool
    @Environment(\.vessInAddSheet) private var inAddSheet

    func body(content: Content) -> some View {
        if inAddSheet {
            content
        } else if clipsUnderBar {
            content
                .mask {
                    Rectangle().ignoresSafeArea(edges: .bottom)
                }
                .modifier(VESSScreenAtmosphere(metric: metric))
        } else {
            content.modifier(VESSScreenAtmosphere(metric: metric))
        }
    }
}

private struct VESSContentTop: ViewModifier {
    let standalone: CGFloat
    @Environment(\.vessInAddSheet) private var inAddSheet

    func body(content: Content) -> some View {
        content.padding(.top, inAddSheet ? VESSSpacing.xl : standalone)
    }
}

/// The canvas with a metric-tinted atmosphere over the top 440 pt.
private struct VESSScreenAtmosphere: ViewModifier {
    let metric: VESSMetricKind?

    func body(content: Content) -> some View {
        content.background(alignment: .top) {
            ZStack(alignment: .top) {
                VESSColor.background
                if let metric {
                    LinearGradient(
                        colors: [metric.atmosphere, metric.atmosphere.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 440)
                }
            }
            .ignoresSafeArea()
        }
    }
}
