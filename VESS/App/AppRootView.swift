import OSLog
import SwiftUI

/// Opens the local store, then shows onboarding or the main tabs depending
/// on whether a profile exists.
struct AppRootView: View {
    @State private var store: LocalStore?
    @State private var lookup: FoodLookupService?
    @State private var health = Self.makeHealth()
    @State private var foodUndo = FoodLogUndo()
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.default
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = Self.makeStore()
        _store = State(initialValue: store)
        _lookup = State(initialValue: store.map { Self.makeLookup(store: $0) })
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
                .animation(.default, value: store.profile == nil)
            } else {
                StoreUnavailableView {
                    store = Self.makeStore()
                    lookup = store.map { Self.makeLookup(store: $0) }
                }
            }
        }
        // Chrome is greyscale; links and CTAs set the link accent themselves.
        .tint(VESSColor.text)
        .preferredColorScheme(appearance.colorScheme)
        // Apple Health is read when the app opens and each time it returns.
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active, let profile = store?.profile else { return }
            Task { await health.refresh(stepsTarget: profile.dailyStepsTarget) }
        }
    }

    /// The live on-device store. Debug builds also accept two launch arguments:
    /// - `-uiTesting`: start with an empty in-memory store (UI tests).
    /// - `-seedProfileOnly`: a profile with history but nothing logged today (S1).
    /// - `-seedSampleData`: start with clearly labeled sample data, in memory,
    ///   never written to the real store.
    private static func makeStore() -> LocalStore? {
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
                }
                return store
            }
            #endif
            return try LocalStore.live()
        } catch {
            Logger(subsystem: "VESS", category: "App").fault("Opening the store failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Apple Health through the read-only HealthKit reader; disconnected
    /// until the user connects. Debug builds use the demo snapshot with
    /// `-seedSampleData`, and accept `-healthSyncing` (S2, D06),
    /// `-healthNotConnected` (S4) and `-healthError` (D07, last known values).
    private static func makeHealth() -> HealthDataStore {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-healthSyncing") {
            return HealthDataStore(state: .syncing)
        }
        if arguments.contains("-seedSampleData") {
            let demo = MockData(now: AppClock.now, calendar: .current).health
            let service = DemoHealthService(snapshot: demo)
            if arguments.contains("-healthNotConnected") {
                return HealthDataStore(state: .notConnected, service: service, didRequestAccess: false)
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

    /// Online lookups use Open Food Facts. UI tests (`-uiTesting`) never touch
    /// the network, so they behave as if offline.
    private static func makeLookup(store: LocalStore) -> FoodLookupService {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
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
            Text("VESS couldn't open your data on this iPhone. Your data hasn't been changed.")
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.vessPrimary)
                .frame(maxWidth: 240)
        }
        .background(VESSColor.background)
    }
}
