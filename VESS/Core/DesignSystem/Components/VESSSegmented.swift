import SwiftUI

/// A capsule segmented control whose selected pill slides between options.
/// Used for Day / Week / Month and Week / Recipes / Grocery.
struct VESSSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringResource)]

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Button {
                    withAnimation(reduceMotion ? nil : VESSMotion.selection) { selection = option.value }
                } label: {
                    Text(option.title)
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum - 6)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(VESSColor.borderStrong)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(VESSColor.fill))
        .sensoryFeedback(.selection, trigger: selection)
    }
}
