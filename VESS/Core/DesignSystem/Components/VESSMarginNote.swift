import SwiftUI

/// A Margin Note: a short, contextual observation set beside the day's
/// content, like a note in the margin of a page. VESS uses these in place
/// of a chat assistant.
///
/// Pale green surface with a thin leading rule. Not a card inside a card:
/// always place it directly on the screen background.
struct VESSMarginNote<Footer: View>: View {
    var label: LocalizedStringKey = "Margin note"
    let text: Text
    var detail: Text?
    @ViewBuilder var footer: Footer

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)

        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            Label(label, systemImage: "sparkle")
                .labelStyle(.titleAndIcon)
                .font(.footnote)
                .foregroundStyle(VESSColor.accent)

            text
                .vessTextStyle(.body)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                detail
                    .vessTextStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VESSSpacing.lg)
        .background(VESSColor.accentPale, in: shape)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(VESSColor.accent)
                .frame(width: 2)
                .padding(.vertical, VESSSpacing.lg)
        }
        .accessibilityElement(children: .combine)
    }
}

extension VESSMarginNote where Footer == EmptyView {
    init(label: LocalizedStringKey = "Margin note", text: Text, detail: Text? = nil) {
        self.init(label: label, text: text, detail: detail, footer: { EmptyView() })
    }
}
