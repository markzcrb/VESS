import SwiftUI

/// Swipe a row left to reveal Delete, for rows in a hairline list (not a
/// `List`). Horizontal drags only, so the page still scrolls; VoiceOver
/// gets a Delete action instead of the gesture. The caller offers Undo.
struct VESSSwipeToDelete<Content: View>: View {
    /// The row's own background, so the revealed button stays behind it.
    var background: Color = VESSColor.background
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @ScaledMetric(relativeTo: .body) private var revealWidth: CGFloat = 88

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button {
                    close()
                    onDelete()
                } label: {
                    Text("Delete")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.criticalText)
                        .frame(width: revealWidth)
                        .frame(maxHeight: .infinity)
                        .background(VESSColor.criticalTint)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            content
                .background(background)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let start: CGFloat = isOpen ? -revealWidth : 0
                            offset = min(0, max(-revealWidth * 1.4, start + value.translation.width))
                        }
                        .onEnded { value in
                            let start: CGFloat = isOpen ? -revealWidth : 0
                            let shouldOpen = start + value.translation.width < -revealWidth / 2
                            withAnimation(reduceMotion ? nil : VESSMotion.selection) {
                                isOpen = shouldOpen
                                offset = shouldOpen ? -revealWidth : 0
                            }
                        }
                )
        }
        .clipped()
        .accessibilityAction(named: Text("Delete"), onDelete)
    }

    private func close() {
        withAnimation(reduceMotion ? nil : VESSMotion.selection) {
            isOpen = false
            offset = 0
        }
    }
}
