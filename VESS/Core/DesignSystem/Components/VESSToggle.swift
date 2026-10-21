import SwiftUI

/// The redesign's switch: on is a light track with a dark knob (dark track,
/// light knob in Light), off is a quiet track with a grey knob. The system
/// switch keeps a white knob, which disappears on the light "on" track.
struct VESSToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : VESSMotion.selection) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 0) {
                configuration.label
                Spacer(minLength: VESSSpacing.md)
                Capsule()
                    .fill(configuration.isOn ? VESSColor.accentFill : VESSColor.borderStrong)
                    .frame(width: 52, height: 32)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? VESSColor.background : VESSColor.tertiaryText)
                            .padding(3)
                    }
                    .opacity(isEnabled ? 1 : 0.4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == VESSToggleStyle {
    static var vess: VESSToggleStyle { VESSToggleStyle() }
}
