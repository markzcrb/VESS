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

    @FocusState private var isFocused: Bool

    init(
        _ title: LocalizedStringKey,
        text: Binding<String>,
        prompt: Text? = nil,
        unit: LocalizedStringKey? = nil
    ) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.unit = unit
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous)

        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            // The field itself carries the label for VoiceOver.
            Text(title)
                .vessTextStyle(.label)
                .accessibilityHidden(true)

            HStack(spacing: VESSSpacing.xs) {
                TextField(title, text: $text, prompt: prompt)
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
            .overlay(shape.strokeBorder(isFocused ? VESSColor.accent : .clear, lineWidth: 1.5))
            .contentShape(shape)
            .onTapGesture { isFocused = true }
        }
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
