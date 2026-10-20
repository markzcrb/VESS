import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// Pins a screen's primary action to the bottom edge, on the card surface.
    ///
    /// While the keyboard is up the action is hidden: the floating keyboard
    /// bar (with "Done") would otherwise sit on top of it. Closing the
    /// keyboard brings it back.
    func vessBottomAction<Action: View>(@ViewBuilder _ action: () -> Action) -> some View {
        modifier(VESSBottomActionModifier(action: action()))
    }
}

private struct VESSBottomActionModifier<Action: View>: ViewModifier {
    let action: Action
    @State private var isKeyboardVisible = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardVisible {
                    action
                        .padding(.horizontal, VESSSpacing.screenInset)
                        .padding(.vertical, VESSSpacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(VESSColor.card)
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
