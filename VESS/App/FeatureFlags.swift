import Foundation

/// Screens that exist only as static designs until their backends are
/// approved (Coach and photo estimate need AI; VESS+ needs StoreKit).
/// They are reachable in Debug builds only and never in Release.
enum VESSFeatureFlags {
    #if DEBUG
    static let photoEstimate = true
    static let coach = true
    static let vessPlus = true
    #else
    static let photoEstimate = false
    static let coach = false
    static let vessPlus = false
    #endif
}
