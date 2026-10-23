import SwiftUI

/// A selectable option for single-choice questions: a hairline row (place it
/// in a `VESSRowGroup`) with a checkmark when selected. The check and the
/// selected trait carry the meaning, not colour.
struct VESSOptionRow: View {
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: VESSSpacing.sm) {
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    Text(title)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                    if let detail {
                        Text(detail)
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(VESSColor.text)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, VESSSpacing.sm)
            .frame(minHeight: VESSSize.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .vessHaptic(.selection, trigger: isSelected)
    }
}
