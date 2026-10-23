import SwiftUI

/// Swipe a row left to reveal Delete, for rows in a hairline list (not a
/// `List`). Horizontal drags only, so the page still scrolls; VoiceOver
/// gets a Delete action instead of the gesture. The caller offers Undo.
///
/// Tapping the row calls `onTap`. The row must not be a `Button`: a button
/// takes the touch before the drag can, so the swipe never starts. A tap
/// gesture fails as soon as the finger moves, and the drag runs alongside
/// the scroll view's own pan.
struct VESSSwipeToDelete<Content: View>: View {
    /// The row's own background, so the revealed button stays behind it.
    var background: Color = VESSColor.background
    var onTap: (() -> Void)?
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
                .contentShape(Rectangle())
                .offset(x: offset)
                .onTapGesture {
                    if isOpen { close() } else { onTap?() }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let start: CGFloat = isOpen ? -revealWidth : 0
                            offset = min(0, max(-revealWidth * 1.4, start + value.translation.width))
                        }
                        .onEnded { value in
                            // A scroll, not a swipe: put the row back as it was.
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                withAnimation(reduceMotion ? nil : VESSMotion.selection) { offset = isOpen ? -revealWidth : 0 }
                                return
                            }
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityAction { onTap?() }
        .accessibilityAction(named: Text("Delete"), onDelete)
    }

    private func close() {
        withAnimation(reduceMotion ? nil : VESSMotion.selection) {
            isOpen = false
            offset = 0
        }
    }
}
