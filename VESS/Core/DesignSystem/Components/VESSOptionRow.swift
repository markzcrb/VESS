import SwiftUI

/// A full-width selectable option, used for single-choice questions.
/// Selection shows a filled check *and* a stronger outline.
struct VESSOptionRow: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous)

        Button(action: action) {
            HStack(spacing: VESSSpacing.sm) {
                VStack(alignment: .leading, spacing: VESSSpacing.xxs / 2) {
                    Text(title)
                        .vessTextStyle(.body)
                    if let detail {
                        Text(detail)
                            .vessTextStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? VESSColor.text : VESSColor.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, VESSSpacing.lg)
            .padding(.vertical, VESSSpacing.md)
            .frame(minHeight: 56)
            .background(isSelected ? VESSColor.accentPale : VESSColor.card, in: shape)
            .overlay(shape.strokeBorder(isSelected ? VESSColor.text : VESSColor.divider, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
