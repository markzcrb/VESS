import OSLog
import SwiftUI

/// Opens the local store, then shows onboarding or the main tabs depending
/// on whether a profile exists.
struct AppRootView: View {
    @State private var store: LocalStore? = Self.makeStore()

    var body: some View {
        Group {
            if let store {
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
                .animation(.default, value: store.profile == nil)
            } else {
                StoreUnavailableView { store = Self.makeStore() }
            }
        }
        .tint(VESSColor.accent)
    }

    /// The live on-device store. Debug builds also accept two launch arguments:
    /// - `-uiTesting`: start with an empty in-memory store (UI tests).
    /// - `-seedSampleData`: start with clearly labeled sample data, in memory,
    ///   never written to the real store.
    private static func makeStore() -> LocalStore? {
        do {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uiTesting") || arguments.contains("-seedSampleData") {
                let store = try LocalStore.inMemory()
                if arguments.contains("-seedSampleData") {
                    try store.seed(MockData(now: .now, calendar: .current))
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
