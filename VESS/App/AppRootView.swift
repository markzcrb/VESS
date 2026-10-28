import OSLog
import SwiftUI

/// Opens the local store, then shows onboarding or the main tabs depending
/// on whether a profile exists.
struct AppRootView: View {
    @State private var store: LocalStore?
    @State private var lookup: FoodLookupService?
    @State private var health = Self.makeHealth()
    @State private var foodUndo = FoodLogUndo()
    @State private var reminders = Self.makeReminders()
    @State private var haptics = VESSHaptics()
    @State private var account = AccountStore.make()
    @State private var consent = AIConsentStore.make()
    @State private var catalog = RecipeCatalog()
    /// USDA generic foods, read in the background with the recipes.
    @State private var genericFoods = GenericFoodDatabase()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.default
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The on-disk store is opening off the main thread.
    @State private var isOpening: Bool

    init() {
        // DEBUG flags build an in-memory store at once (captures, UI tests);
        // the real store opens in the background (see `openLiveStore`).
        let store = Self.makeDebugStore()
        _store = State(initialValue: store)
        _lookup = State(initialValue: store.map { Self.makeLookup(store: $0) })
        _isOpening = State(initialValue: store == nil)
        if store != nil { LaunchTiming.mark("store") }
    }

    var body: some View {
        Group {
            if let store, let lookup {
                Group {
                    if store.profile == nil {
                        OnboardingFlow()
                            .transition(.opacity)
                    } else {
                        RootTabView()
                            .transition(.opacity)
                    }
                }
                .environment(store)
                .environment(lookup)
                .environment(health)
                .environment(foodUndo)
                .environment(reminders)
                .environment(account)
                .environment(consent)
                .environment(catalog)
                .environment(genericFoods)
                // The bundled recipes and generic foods, read in the background
                // once the UI is up.
                .task { await catalog.load(foods: genericFoods) }
                #if DEBUG
                // The VESS+ trial reminder goes once the trial converts or is cancelled.
                .task { await VESSPlusTrial.watch(reminders) }
                #endif
                .animation(reduceMotion ? VESSMotion.reducedCrossfade : .default, value: store.profile == nil)
                // One success tap for every log, wherever it came from.
                .vessHaptic(.success, trigger: foodUndo.loggedCount)
            } else if isOpening {
                // The launch screen's colour while the store opens.
                VESSColor.background
                    .ignoresSafeArea()
                    .task { await openLiveStore() }
            } else {
                StoreUnavailableView {
                    isOpening = true
                }
            }
        }
        .vessHapticsHost(haptics)
        // Chrome is greyscale; links and CTAs set the link accent themselves.
        .tint(VESSColor.text)
        .onAppear { LaunchTiming.firstFrame() }
        .preferredColorScheme(appearance.colorScheme)
        // Apple Health is read when the app opens and each time it returns.
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { refreshOnActive() }
        }
        // A meal logged today drops its reminder.
        .onChange(of: store?.foodEntries(on: AppClock.now, calendar: .current).count) {
            guard let store else { return }
            Task { await reminders.sync(store: store) }
        }
    }

    /// The live on-device store. Debug builds also accept two launch arguments:
    /// - `-uiTesting`: start with an empty in-memory store (UI tests).
    /// - `-seedProfileOnly`: a profile with history but nothing logged today (S1).
    /// - `-seedSampleData`: start with clearly labeled sample data, in memory,
    ///   never written to the real store.
    private func refreshOnActive() {
        guard let store, let profile = store.profile else { return }
        Task {
            await health.refresh(stepsTarget: profile.dailyStepsTarget)
            await reminders.sync(store: store)
        }
    }

    /// Opens the on-disk store: the container (and any migration) off the
    /// main thread, then the store on it.
    private func openLiveStore() async {
        do {
            let container = try await Task.detached(priority: .userInitiated) { try LocalStore.liveContainer() }.value
            let opened = LocalStore(container: container)
            store = opened
            lookup = Self.makeLookup(store: opened)
            LaunchTiming.mark("store")
            // The launch's "became active" came before the store was open.
            if scenePhase == .active { refreshOnActive() }
        } catch {
            Logger(subsystem: AppLog.subsystem, category: "App").fault("Opening the store failed: \(error.localizedDescription, privacy: .public)")
        }
        isOpening = false
    }

    /// With DEBUG launch flags, an in-memory store with sample data; otherwise
    /// `nil`, and the real store opens in the background.
    private static func makeDebugStore() -> LocalStore? {
        do {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uiTesting") || arguments.contains("-seedSampleData") || arguments.contains("-seedProfileOnly") {
                let store = try LocalStore.inMemory()
                let data = MockData(now: AppClock.now, calendar: .current)
                if arguments.contains("-seedProfileOnly") {
                    // S1: a profile and history, nothing logged today.
                    try store.saveProfile(data.profile)
                    for entry in data.foodHistory { try store.add(entry) }
                } else if arguments.contains("-seedSampleData") {
                    try store.seed(data)
                    // I09: dinner and two extras logged, a full day.
                    if arguments.contains("-seedFullDay") {
                        for entry in data.fullDayExtras { try store.add(entry) }
                    }
                    // 14: six habits with four weeks of ticks.
                    if arguments.contains("-habitsDemo") {
                        try MockData.seedHabits(into: store, now: AppClock.now, calendar: .current)
                    }
                    // R02: six own recipes, two from AI Chef, some cooked before.
                    if arguments.contains("-recipesDemo") {
                        try MockData.seedRecipes(into: store, now: AppClock.now, calendar: .current)
                    }
                    // AI Chef's on-device check (UI test): also allergic to soy.
                    if arguments.contains("-allergicToSoy"), var profile = store.profile {
                        profile.allergies.insert(.soy)
                        try store.saveProfile(profile)
                    }
                    // 13: cycle tracking on, with six cycles of history
                    // (`-cycleOn`) or nothing logged yet (`-cycleOnEmpty`).
                    if arguments.contains("-cycleOn") || arguments.contains("-cycleOnEmpty"), var profile = store.profile {
                        profile.cycleTrackingEnabled = true
                        try store.saveProfile(profile)
                        if arguments.contains("-cycleOn") {
                            for day in MockData.cycleDays(now: AppClock.now, calendar: .current) {
                                try store.save(day, calendar: .current)
                            }
                        }
                    }
                }
                return store
            }
            #endif
            return nil
        } catch {
            Logger(subsystem: AppLog.subsystem, category: "App").fault("Opening the store failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Apple Health through the read-only HealthKit reader; disconnected
    /// until the user connects. Debug builds use the demo snapshot with
    /// `-seedSampleData`, and accept `-healthSyncing` (S2, D06),
    /// `-healthNotConnected` (S4), `-healthNothingShared`, `-healthError`
    /// (D07, last known values) and `-healthStale` (last read 3 h ago).
    private static func makeHealth() -> HealthDataStore {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-healthSyncing") {
            return HealthDataStore(state: .syncing)
        }
        if arguments.contains("-seedSampleData") {
            let demo = MockData(now: AppClock.now, calendar: .current).health
            let service = DemoHealthService(snapshot: demo)
            if arguments.contains("-healthNothingShared") {
                return HealthDataStore(state: .nothingShared, service: service, didRequestAccess: false)
            }
            if arguments.contains("-healthNotConnected") {
                return HealthDataStore(state: .notConnected, service: service, didRequestAccess: false)
            }
            // Last read 3 hours ago, and the read at launch fails: Today dims
            // its Health rings, with Retry (which then succeeds).
            if arguments.contains("-healthStale") {
                let failsOnce = DemoHealthService(snapshot: demo, failsFirst: .init())
                return HealthDataStore(state: .available(demo), service: failsOnce, didRequestAccess: true,
                                       lastSuccessAt: AppClock.now.addingTimeInterval(-3 * 3600))
            }
            if arguments.contains("-healthError") {
                return HealthDataStore(state: .failed(lastKnown: demo), service: DemoHealthService(snapshot: demo, fails: true), didRequestAccess: true)
            }
            return HealthDataStore(state: .available(demo), service: service, didRequestAccess: false)
        }
        if arguments.contains("-uiTesting") {
            return HealthDataStore()
        }
        #endif
        return HealthDataStore(service: HealthKitService())
    }

    /// UI tests never schedule notifications.
    private static func makeReminders() -> ReminderService {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            return ReminderService(center: nil)
        }
        #endif
        return ReminderService()
    }

    /// Online lookups use Open Food Facts. UI tests (`-uiTesting`) never touch
    /// the network, so they behave as if offline.
    private static func makeLookup(store: LocalStore) -> FoodLookupService {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // `-foodOffline` shows the offline search state in captures.
        if arguments.contains("-uiTesting") || arguments.contains("-foodOffline") {
            return FoodLookupService(store: store, provider: OfflineFoodProvider())
        }
        #endif
        return FoodLookupService(store: store, provider: OpenFoodFactsClient())
    }
}

/// Shown only if on-device storage can't be opened.
private struct StoreUnavailableView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.circle")
        } description: {
            Text("UMEVA couldn't open your data on this iPhone. Your data hasn't been changed.")
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.vessPrimary)
                .frame(maxWidth: 240)
        }
        .background(VESSColor.background)
    }
}
