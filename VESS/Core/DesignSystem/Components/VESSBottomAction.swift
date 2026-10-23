import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// Pins a screen's primary action to the bottom edge, on the card surface
    /// (or `background`, to match a screen drawn on the canvas; inside the
    /// Add sheet always the sheet's canvas). Content scrolls under a 16 pt
    /// fade above the action, and the scroll view's bottom inset includes
    /// that fade, so the last field ends clear of the button.
    ///
    /// While the keyboard is up the action is hidden: the floating keyboard
    /// bar (with "Done") would otherwise sit on top of it. Closing the
    /// keyboard brings it back.
    func vessBottomAction<Action: View>(background: Color = VESSColor.card, @ViewBuilder _ action: () -> Action) -> some View {
        modifier(VESSBottomActionModifier(action: action(), background: background))
    }
}

private struct VESSBottomActionModifier<Action: View>: ViewModifier {
    let action: Action
    let background: Color
    @Environment(\.vessInAddSheet) private var inAddSheet
    @State private var isKeyboardVisible = false

    func body(content: Content) -> some View {
        let surface = inAddSheet ? VESSColor.background : background
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isKeyboardVisible {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [surface.opacity(0), surface], startPoint: .top, endPoint: .bottom)
                            .frame(height: VESSSpacing.md)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        action
                            .padding(.horizontal, VESSSpacing.screenInset)
                            .padding(.bottom, VESSSpacing.sm)
                            .frame(maxWidth: .infinity)
                            // Down to the screen edge, so scrolled content never
                            // shows below the action (home indicator area).
                            .background(surface.ignoresSafeArea(edges: .bottom))
                    }
                }
            }
            #if canImport(UIKit)
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                    isKeyboardVisible = true
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillHideNotification) {
                    isKeyboardVisible = false
                }
            }
            #endif
    }
}
