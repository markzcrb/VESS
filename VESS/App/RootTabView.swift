import SwiftUI

/// Top-level destinations: four tabs plus the Add action.
enum AppTab: Hashable {
    case today
    case nutrition
    case plan
    case you
    /// Not a destination: selecting it opens the Add sheet.
    case add
}

/// The app's navigation shell: the native tab bar with Today, Nutrition,
/// Plan and You, and Add as the separate trailing button. Each tab owns its
/// own `NavigationStack`.
struct RootTabView: View {
    @State private var selection: AppTab = .today
    @State private var addRequest: AddFoodRequest?

    private let calendar = Calendar.current

    var body: some View {
        TabView(selection: tabSelection) {
            Tab(value: .today) {
                TodayView(selectedTab: $selection)
                    .vessFoodUndoToast()
            } label: {
                tabLabel("Today", icon: .symbol("sun.max"), tab: .today)
            }
            Tab(value: .nutrition) {
                NutritionView()
                    .vessFoodUndoToast()
            } label: {
                tabLabel("Nutrition", icon: .asset(.tabFork), tab: .nutrition)
            }
            Tab(value: .plan) {
                PlanView()
                    .vessFoodUndoToast()
            } label: {
                tabLabel("Plan", icon: .asset(.tabCalendar), tab: .plan)
            }
            Tab(value: .you) {
                ProfileView()
                    .vessFoodUndoToast()
            } label: {
                tabLabel("You", icon: .symbol("person"), tab: .you)
            }
            // The pinned trailing slot draws Add as its own circle.
            Tab("Add", systemImage: "plus", value: .add, role: .prominent) {
                Color.clear
            }
        }
        .tint(VESSColor.text)
        .sheet(item: $addRequest) { request in
            FoodSearchSheet(request: request)
        }
    }

    private enum TabIcon {
        case symbol(String)
        case asset(ImageResource)
    }

    /// Outline icons for every tab. Unselected icons are pre-tinted and drawn
    /// as originals, so the glass bar shows them dimmed like the reference.
    private func tabLabel(_ title: LocalizedStringResource, icon: TabIcon, tab: AppTab) -> some View {
        Label {
            Text(title)
        } icon: {
            tabImage(icon, isSelected: selection == tab)
        }
    }

    private func tabImage(_ icon: TabIcon, isSelected: Bool) -> Image {
        let base: UIImage? = switch icon {
        case .symbol(let name): UIImage(systemName: name)
        case .asset(let resource): UIImage(resource: resource)
        }
        guard let base else { return Image(systemName: "questionmark") }
        if isSelected {
            return Image(uiImage: base.withRenderingMode(.alwaysTemplate))
        }
        return Image(uiImage: base.withTintColor(UIColor(VESSColor.tertiaryText), renderingMode: .alwaysOriginal))
    }

    /// Selecting Add presents the sheet and leaves the current tab selected.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .add {
                    addRequest = AddFoodRequest(meal: .likely(at: AppClock.now, calendar: calendar), day: AppClock.now)
                } else {
                    selection = newValue
                }
            }
        )
    }
}

#Preview("Dark") {
    RootTabView()
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    RootTabView()
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.light)
}
