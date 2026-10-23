import SwiftUI

/// A horizontally scrolling row (chips, tabs) inside a padded screen. At
/// rest it starts at the content margin; scrolled, it runs off both screen
/// edges instead of being cut at the margin, which also hints that it
/// scrolls.
struct VESSBleedingRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .contentMargins(.horizontal, VESSSpacing.screenInset, for: .scrollContent)
        .padding(.horizontal, -VESSSpacing.screenInset)
    }
}
