import SwiftUI

/// A search field on a raised fill with a hairline: magnifier, field, and a
/// clear button once something is typed. An optional trailing accessory
/// (the food search's barcode button) sits after a divider.
struct VESSSearchField<Accessory: View>: View {
    let prompt: LocalizedStringResource
    @Binding var text: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: VESSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VESSColor.secondaryText)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityHidden(true)
            // The placeholder is drawn here: the system one is under 4.5:1,
            // and a custom prompt loses the scaled font at large sizes.
            TextField(String(localized: prompt), text: $text, prompt: Text(verbatim: ""))
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
                .background(alignment: .leading) {
                    if text.isEmpty {
                        Text(prompt)
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.tertiaryText)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                }
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(VESSColor.tertiaryText)
                        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            accessory
        }
        .padding(.leading, VESSSpacing.md)
        .padding(.trailing, VESSSpacing.xxs)
        .frame(minHeight: VESSHitTarget.control)
        .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous).strokeBorder(VESSColor.divider))
    }
}

extension VESSSearchField where Accessory == EmptyView {
    init(prompt: LocalizedStringResource, text: Binding<String>) {
        self.init(prompt: prompt, text: text) { EmptyView() }
    }
}
