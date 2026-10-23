import Foundation

/// Screens that exist only as static designs until their backends are
/// approved (photo estimate until item 4; VESS+ needs StoreKit).
/// They are reachable in Debug builds only and never in Release.
enum VESSFeatureFlags {
    #if DEBUG
    static let photoEstimate = true
    static let vessPlus = true
    #else
    static let photoEstimate = false
    static let vessPlus = false
    #endif
}
