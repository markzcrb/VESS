import Foundation

/// Screens that exist only as static designs until their backends are
/// approved (VESS+ needs StoreKit).
/// They are reachable in Debug builds only and never in Release.
enum VESSFeatureFlags {
    #if DEBUG
    static let vessPlus = true
    #else
    static let vessPlus = false
    #endif
}
