import SwiftUI

/// The user's appearance choice (You › Appearance). VESS is designed dark
/// first, so Dark is the default; System follows the device.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// `@AppStorage` key.
    static let storageKey = "appearance"
    static let `default`: AppAppearance = .dark

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` lets the system decide.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
