import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A labeled text field with an optional trailing unit, such as "kg" or "cm".
///
/// Configure keyboard and content type at the call site:
///
///     VESSTextField("Weight", text: $weight, unit: "kg")
///         .keyboardType(.decimalPad)
struct VESSTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var prompt: Text?
    var unit: LocalizedStringKey?
    /// A calm, amber message below the field, such as "Add calories to save."
    var error: Text?

    @FocusState private var isFocused: Bool

    init(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        prompt: Text? = nil,
        unit: LocalizedStringKey? = nil,
        error: Text? = nil
    ) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.unit = unit
        self.error = error
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous)

        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            // The field itself carries the label for VoiceOver.
            Text(title)
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
                .accessibilityHidden(true)

            HStack(spacing: VESSSpacing.xs) {
                // No placeholder unless given: the label above already names the field.
                TextField(title, text: $text, prompt: prompt ?? Text(verbatim: ""))
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(VESSColor.text)
                    // With a prompt, SwiftUI would otherwise use the prompt as the label.
                    .accessibilityLabel(Text(title))

                if let unit {
                    Text(unit)
                        .vessTextStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, VESSSpacing.md)
            .frame(minHeight: VESSHitTarget.control)
            .background(VESSColor.fill, in: shape)
            .overlay(shape.strokeBorder(borderColor, lineWidth: error != nil || isFocused ? 1.5 : 1))
            .contentShape(shape)
            .onTapGesture { isFocused = true }
            .accessibilityHint(error ?? Text(verbatim: ""))

            if let error {
                error
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.warningText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    private var borderColor: Color {
        if error != nil { return VESSColor.warning }
        return isFocused ? VESSColor.borderStrong : VESSColor.divider
    }
}

extension View {
    /// Adds a "Done" button above the keyboard. Number pads have no Return
    /// key, so every screen with VESS fields applies this once (not per field,
    /// which would duplicate the button).
    func vessKeyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                }
                .accessibilityIdentifier("keyboard.done")
            }
        }
    }
}
