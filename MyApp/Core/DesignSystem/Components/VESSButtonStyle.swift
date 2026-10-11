import SwiftUI

/// Button styles for VESS. Use one `.vessPrimary` button per screen at most.
///
///     Button("Continue") { … }
///         .buttonStyle(.vessPrimary)
struct VESSButtonStyle: ButtonStyle {
    enum Variant {
        /// Filled green, full width, for the screen's primary action.
        case primary
        /// Quiet filled surface, full width, for an equal-weight alternative.
        case secondary
        /// Green text only, for low-emphasis actions such as "Add to lunch".
        case tertiary
        /// Compact capsule for inline quick actions such as "+250 ml".
        case quick
    }

    let variant: Variant

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .multilineTextAlignment(.center)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: isFullWidth ? .infinity : nil, minHeight: minHeight)
            .foregroundStyle(foreground)
            .background(background, in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion && variant != .tertiary ? 0.98 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: configuration.isPressed)
    }

    private var isFullWidth: Bool {
        variant == .primary || variant == .secondary
    }

    private var shape: AnyShape {
        variant == .quick
            ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
    }

    private var font: Font {
        switch variant {
        case .primary, .secondary: .body.weight(.semibold)
        case .tertiary: .body
        case .quick: .subheadline.weight(.medium)
        }
    }

    private var horizontalPadding: CGFloat {
        variant == .tertiary ? 0 : VESSSpacing.lg
    }

    private var minHeight: CGFloat {
        isFullWidth ? VESSHitTarget.control : VESSHitTarget.minimum
    }

    private var foreground: Color {
        switch variant {
        case .primary: VESSColor.onAccent
        case .secondary, .quick: VESSColor.text
        case .tertiary: VESSColor.accent
        }
    }

    private var background: Color {
        switch variant {
        case .primary: VESSColor.accent
        case .secondary, .quick: VESSColor.fill
        case .tertiary: .clear
        }
    }
}

extension ButtonStyle where Self == VESSButtonStyle {
    static var vessPrimary: VESSButtonStyle { VESSButtonStyle(variant: .primary) }
    static var vessSecondary: VESSButtonStyle { VESSButtonStyle(variant: .secondary) }
    static var vessTertiary: VESSButtonStyle { VESSButtonStyle(variant: .tertiary) }
    static var vessQuick: VESSButtonStyle { VESSButtonStyle(variant: .quick) }
}
