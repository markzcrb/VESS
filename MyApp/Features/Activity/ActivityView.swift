import SwiftUI

/// Placeholder. Phase 4 builds workouts, scheduling and history here.
struct ActivityView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Activity",
                systemImage: "figure.walk",
                description: Text("Schedule workouts, mark them complete and look back at your history.")
            )
            .background(VESSColor.background)
            .navigationTitle("Activity")
        }
    }
}

#Preview {
    ActivityView()
}
