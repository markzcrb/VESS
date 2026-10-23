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
    /// Counts taps on Add; see `tabSelection`.
    @State private var addTaps = 0

    private let calendar = Calendar.current

    var body: some View {
        // Read here so each Add tap re-renders the tab view.
        let _ = addTaps
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
    ///
    /// The tab bar selects the (empty) Add tab before asking the binding,
    /// and nothing told it to go back, so its blank content stayed on screen
    /// until the sheet's first build finished (about 2 s, sometimes dropping
    /// the sheet). Bumping `addTaps` re-renders the tab view at once, so it
    /// reads `selection` again and returns to the current tab; the sheet is
    /// presented on the next turn of the run loop, after that.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                guard newValue == .add else {
                    selection = newValue
                    return
                }
                addTaps += 1
                Task { @MainActor in
                    addRequest = AddFoodRequest(meal: .likely(at: AppClock.now, calendar: calendar), day: AppClock.now)
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
