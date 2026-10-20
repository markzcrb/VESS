import SwiftUI

/// Activity: a detail screen pushed from Today's Steps row, not a tab.
/// Placeholder until the Activity screens (09, D01–D07) are built.
struct ActivityView: View {
    var body: some View {
        ContentUnavailableView(
            "Activity",
            systemImage: "figure.walk",
            description: Text("Workouts, steps and history will appear here.")
        )
        .vessScreenBackground(.activity)
        .vessDetailTitle("Activity")
    }
}

#Preview {
    NavigationStack {
        ActivityView()
    }
    .preferredColorScheme(.dark)
}
