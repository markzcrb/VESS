import SwiftUI

/// Placeholder. Phase 5 builds meal planning, groceries and expiration tracking here.
struct PlanView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Plan",
                systemImage: "calendar",
                description: Text("Plan meals, keep a grocery list and see what's at home before it expires.")
            )
            .background(VESSColor.background)
            .navigationTitle("Plan")
        }
    }
}

#Preview {
    PlanView()
}
