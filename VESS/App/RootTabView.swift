import OSLog
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
    /// The Add sheet is on its way down: a new "+" waits for it to finish.
    @State private var isAddDismissing = false
    /// A "+" made while the sheet was going down, shown once it's gone.
    @State private var pendingAdd: AddFoodRequest?
    /// Counts taps on Add; see `tabSelection`.
    @State private var addTaps = 0
    /// Builds the Add sheet once, off screen, soon after launch.
    @State private var isPrewarming = false
    @State private var didPrewarm = false

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
        .vessHaptic(.selection, trigger: selection)
        .vessHaptic(.add, trigger: addTaps)
        // Entry points elsewhere open the same sheet on their type.
        .environment(\.vessOpenAdd, VESSOpenAddAction { type in
            requestAdd(type)
        })
        .sheet(item: Binding(
            get: { addRequest },
            set: { new in
                // Dismissal starts here; it finishes in onDismiss.
                if new == nil, addRequest != nil { isAddDismissing = true }
                addRequest = new
            }
        ), onDismiss: {
            isAddDismissing = false
            if let pendingAdd {
                self.pendingAdd = nil
                addRequest = pendingAdd
            }
        }) { request in
            AddSheet(request: request)
        }
        // Pre-warm (first "+" took 1–1.5 s): a few seconds after launch,
        // build the sheet's content and search field one time, invisibly,
        // so a later first tap only has to present it.
        .background {
            if isPrewarming {
                AddSheet(request: AddFoodRequest(meal: .likely(at: AppClock.now, calendar: calendar), day: AppClock.now, type: .food))
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .task {
                        try? await Task.sleep(for: .milliseconds(400))
                        isPrewarming = false
                    }
            }
        }
        .task {
            guard !didPrewarm else { return }
            didPrewarm = true
            // Late enough not to compete with the first taps after launch
            // (at 1 s it landed right on them); a "+" before then just
            // builds the sheet itself.
            try? await Task.sleep(for: .seconds(4))
            guard addRequest == nil else { return }
            isPrewarming = true
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

    /// Made once per icon and state: building them on every body pass cost
    /// ~110 ms of the first frame.
    private static var tabImages: [String: Image] = [:]

    private func tabImage(_ icon: TabIcon, isSelected: Bool) -> Image {
        let key: String = switch icon {
        case .symbol(let name): "\(name).\(isSelected)"
        case .asset(let resource): "\(String(describing: resource)).\(isSelected)"
        }
        if let cached = Self.tabImages[key] { return cached }
        let base: UIImage? = switch icon {
        case .symbol(let name): UIImage(systemName: name)
        case .asset(let resource): UIImage(resource: resource)
        }
        guard let base else { return Image(systemName: "questionmark") }
        let image = isSelected
            ? Image(uiImage: base.withRenderingMode(.alwaysTemplate))
            : Image(uiImage: base.withTintColor(UIColor(VESSColor.tertiaryText), renderingMode: .alwaysOriginal))
        Self.tabImages[key] = image
        return image
    }

    /// Opens the Add sheet, or, while the last one is still going down,
    /// opens it the moment that finishes, so a "+" is never lost.
    private func requestAdd(_ type: AddType?) {
        let request = AddFoodRequest(meal: .likely(at: AppClock.now, calendar: calendar), day: AppClock.now, type: type)
        if isAddDismissing || addRequest != nil {
            pendingAdd = request
        } else {
            addRequest = request
        }
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
                AddSheetTiming.tapped()
                Task { @MainActor in
                    requestAdd(nil)
                }
            }
        )
    }
}

#if DEBUG
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
#endif

/// DEBUG: how long the first "+" takes, tap to the sheet's content on
/// screen. Console: subsystem "VESS", category "Timing".
enum AddSheetTiming {
    #if DEBUG
    private static var tapDate: Date?
    private static let logger = Logger(subsystem: "VESS", category: "Timing")
    #endif

    static func tapped() {
        #if DEBUG
        tapDate = .now
        #endif
    }

    static func appeared() {
        #if DEBUG
        guard let tapDate else { return }
        Self.tapDate = nil
        logger.notice("Add sheet: tap → appear \(Int(Date.now.timeIntervalSince(tapDate) * 1000), privacy: .public) ms")
        #endif
    }
}
