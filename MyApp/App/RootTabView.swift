import SwiftUI

/// Top-level destinations. Kept to five, as in the product spec.
enum AppTab: Hashable {
    case today
    case nutrition
    case plan
    case activity
    case profile
}

/// The app's navigation shell. Each tab owns its own `NavigationStack`.
struct RootTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.horizon", value: .today) {
                TodayView(selectedTab: $selection)
            }
            Tab("Nutrition", systemImage: "fork.knife", value: .nutrition) {
                NutritionView()
            }
            Tab("Plan", systemImage: "calendar", value: .plan) {
                PlanView()
            }
            Tab("Activity", systemImage: "figure.walk", value: .activity) {
                ActivityView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: .profile) {
                ProfileView()
            }
        }
        .tint(VESSColor.accent)
    }
}

#Preview("Light") {
    RootTabView()
        .environment(LocalStore.preview())
}

#Preview("Dark") {
    RootTabView()
        .environment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
