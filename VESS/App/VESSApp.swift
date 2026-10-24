import SwiftUI

@main
struct VESSApp: App {
    init() {
        LaunchTiming.appInit()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
