import SwiftUI

/// Plan. Until the week plan (07) is built, the tab leads to Pantry.
struct PlanView: View {
    @Environment(LocalStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VESSRowGroup {
                    NavigationLink {
                        PantryView()
                    } label: {
                        VESSListRow(
                            systemImage: "refrigerator",
                            title: Text("Pantry"),
                            subtitle: Text("^[\(store.inventory.count) item](inflect: true) at home")
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("plan.pantry")
                }
                .vessHairlineBottom()
                .padding(.horizontal, VESSSpacing.screenInset)
            }
            .vessScreenBackground()
            .navigationTitle("Plan")
        }
    }
}

#Preview {
    PlanView()
        .previewEnvironment(LocalStore.preview())
}
