import SwiftUI

/// Button styles for VESS. Use one `.vessPrimary` button per screen at most.
///
///     Button("Add to dinner") { … }
///         .buttonStyle(.vessPrimary)
struct VESSButtonStyle: ButtonStyle {
    enum Variant {
        /// Light capsule (dark in Light mode), full width: the screen's primary action.
        case primary
        /// Raised capsule with a hairline, full width: an equal-weight alternative.
        case secondary
        /// Link-coloured text only, for low-emphasis actions such as "Add to lunch".
        case quiet
        /// Compact raised capsule for inline quick actions such as "+250 ml".
        case quick
    }

    let variant: Variant

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vessTextStyle(variant == .quick ? .bodyS : .bodyMStrong)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, variant == .quiet ? 0 : VESSSpacing.lg)
            .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: minHeight)
            .background { background }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion && variant != .quiet ? 0.98 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: configuration.isPressed)
    }

    private var isFullWidth: Bool {
        variant == .primary || variant == .secondary
    }

    private var minHeight: CGFloat {
        isFullWidth ? VESSHitTarget.control : VESSHitTarget.minimum
    }

    private var foreground: Color {
        switch variant {
        case .primary: VESSColor.onAccent
        case .secondary, .quick: VESSColor.text
        case .quiet: VESSColor.accent
        }
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .primary:
            Capsule().fill(VESSColor.accentFill)
        case .secondary, .quick:
            Capsule().fill(VESSColor.fill)
                .overlay(Capsule().strokeBorder(VESSColor.divider))
        case .quiet:
            Color.clear
        }
    }
}

extension ButtonStyle where Self == VESSButtonStyle {
    static var vessPrimary: VESSButtonStyle { VESSButtonStyle(variant: .primary) }
    static var vessSecondary: VESSButtonStyle { VESSButtonStyle(variant: .secondary) }
    static var vessQuiet: VESSButtonStyle { VESSButtonStyle(variant: .quiet) }
    static var vessQuick: VESSButtonStyle { VESSButtonStyle(variant: .quick) }
}

/// A round icon button: raised circle with a hairline, or filled (for example
/// an "added" checkmark). 40 pt visual inside a 44 pt hit area.
struct VESSIconButton: View {
    let systemImage: String
    let label: LocalizedStringResource
    var isFilled = false
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var size = VESSSize.iconButton

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(isFilled ? VESSColor.onAccent : VESSColor.text)
                .frame(width: size, height: size)
                .background(Circle().fill(isFilled ? VESSColor.accentFill : VESSColor.fill))
                .overlay(Circle().strokeBorder(VESSColor.divider))
                .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
