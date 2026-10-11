import SwiftUI

/// Semantic color palette for VESS.
///
/// Every color is defined in `Assets.xcassets/Colors` with light and dark
/// variants, so views never hard-code hex values. Light values are the
/// approved VESS palette; dark values come from the approved dark Today mockup.
enum VESSColor {
    // MARK: Surfaces

    /// App canvas. #F7F7F4
    static let background = Color(.vessBackground)
    /// Cards and sheets. #FFFFFF
    static let card = Color(.vessCard)
    /// Recessed surfaces: inputs, quiet buttons, tracks, thumbnails.
    static let fill = Color(.vessFill)
    /// Hairlines and inset separators. #E7E7E2
    static let divider = Color(.vessDivider)

    // MARK: Text

    /// Primary text. #171817
    static let text = Color(.vessText)
    /// Supporting text. #6E716D, WCAG AA on background and card.
    static let secondaryText = Color(.vessSecondaryText)
    /// Decorative and disabled only. #A4A7A2. Never use for text that must be read.
    static let tertiaryText = Color(.vessTertiaryText)

    // MARK: Accent

    /// Primary VESS green. #5F735C
    static let accent = Color(.vessAccent)
    /// Content on top of `accent`.
    static let onAccent = Color(.vessOnAccent)
    /// Soft green for selected states. #DCE6D8
    static let accentSoft = Color(.vessAccentSoft)
    /// Pale green for Margin Notes. #EEF3EB
    static let accentPale = Color(.vessAccentPale)

    // MARK: Data
    // Graphics only (dots, Vessel Lines). Values are always also shown as text.

    static let calories = Color(.vessCalories)
    static let protein = Color(.vessProtein)
    static let carbs = Color(.vessCarbs)
    static let fat = Color(.vessFat)
    static let water = Color(.vessWater)
    static let activity = Color(.vessActivity)

    // MARK: Status

    /// Soon: dots and lines.
    static let warning = Color(.vessWarning)
    /// Soon: text on `warningTint`.
    static let warningText = Color(.vessWarningText)
    static let warningTint = Color(.vessWarningTint)
    /// Now (expires today, expired): text on `criticalTint`. Use rarely.
    static let criticalText = Color(.vessCriticalText)
    static let criticalTint = Color(.vessCriticalTint)
}
