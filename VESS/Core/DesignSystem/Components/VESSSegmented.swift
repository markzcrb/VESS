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
                    // Like the system segmented control, the labels stop
                    // growing at accessibility sizes; a long press shows
                    // the Large Content Viewer instead of a broken word.
                    Text(option.title)
                        .vessTextStyle(.bodyS)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .padding(.horizontal, VESSSpacing.xs)
                        .foregroundStyle(isSelected ? VESSColor.text : VESSColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum)
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
                .accessibilityShowsLargeContentViewer { Text(option.title) }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(VESSColor.fill))
        .vessHaptic(.selection, trigger: selection)
    }
}
