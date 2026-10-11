import SwiftUI

/// A brief confirmation with an Undo action, shown after logging something.
/// Replaces confirmation dialogs: actions happen immediately and can be undone.
struct VESSUndoToast: View {
    let message: Text
    let undo: () -> Void

    var body: some View {
        HStack(spacing: VESSSpacing.md) {
            message
                .font(.subheadline)
                .foregroundStyle(VESSColor.text)
            Spacer(minLength: 0)
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VESSColor.accent)
                .frame(minHeight: VESSHitTarget.minimum)
                .accessibilityIdentifier("undoToast.undo")
        }
        .padding(.horizontal, VESSSpacing.lg)
        .background(VESSColor.card, in: Capsule())
        .overlay(Capsule().strokeBorder(VESSColor.divider, lineWidth: 0.5))
        .vessElevation()
        .padding(.horizontal, VESSSpacing.screenInset)
        .padding(.bottom, VESSSpacing.xs)
    }
}

extension View {
    /// The standard VESS error presentation: a plain message, never raw
    /// technical details. Technical details are logged separately.
    func vessErrorAlert(isPresented: Binding<Bool>, retry: (() -> Void)? = nil) -> some View {
        alert("Something went wrong", isPresented: isPresented) {
            if let retry {
                Button("Try again", action: retry)
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your change wasn't saved. Please try again.")
        }
    }
}
