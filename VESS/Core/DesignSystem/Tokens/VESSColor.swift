import SwiftUI

/// Semantic color palette for VESS.
///
/// Every color is defined in `Assets.xcassets/Colors` with light and dark
/// variants, so views never hard-code hex values. Values follow the
/// dark-first redesign (`Redesign/VessDesignSystem/Theme/VessColor.swift`).
///
/// Colour is data: metric hues appear only on rings, bars, deltas and
/// metric icons. Everything else is greyscale; links and CTAs use `accent`.
enum VESSColor {
    // MARK: Surfaces

    /// App canvas.
    static let background = Color(.vessBackground)
    /// Cards, sheets and grouped content.
    static let card = Color(.vessCard)
    /// Raised controls: inputs, chips, quiet buttons, thumbnails.
    static let fill = Color(.vessFill)
    /// Recessed areas, such as the legend chip.
    static let sunken = Color(.vessSunken)
    /// Hairlines and inset separators.
    static let divider = Color(.vessDivider)
    /// Stronger outlines and the selected segment.
    static let borderStrong = Color(.vessBorderStrong)

    // MARK: Text

    static let text = Color(.vessText)
    static let secondaryText = Color(.vessSecondaryText)
    /// Tertiary text. At least 4.5:1 on every background in both modes.
    static let tertiaryText = Color(.vessTertiaryText)
    /// Axis ticks, dividers and other marks. Never use for text.
    static let decorative = Color(.vessDecorative)

    // MARK: Accent

    /// Link accent: links, CTAs and selected text.
    static let accent = Color(.vessAccent)
    /// Primary button and selected chip fill.
    static let accentFill = Color(.vessAccentFill)
    /// Content on `accentFill`.
    static let onAccent = Color(.vessOnAccent)
    /// Soft link tint for selected states.
    static let accentSoft = Color(.vessAccentSoft)
    /// Neutral raised surface for notes and selected option rows.
    static let accentPale = Color(.vessAccentPale)
    /// VESS sage. Brand assets only (wordmark, welcome), never UI chrome.
    static let brandSage = Color(.vessBrandSage)

    // MARK: Metrics
    // Rings, bars, deltas and metric icons only. Values are always also shown as text.

    static let calories = Color(.vessCalories)
    static let protein = Color(.vessProtein)
    static let carbs = Color(.vessCarbs)
    static let fat = Color(.vessFat)
    static let water = Color(.vessWater)
    static let activity = Color(.vessActivity)
    /// Cycle tracking: logged and estimated period days, the cycle ring.
    static let cycle = Color(.vessCycle)

    // MARK: Status

    static let statusOptimal = Color(.vessStatusOptimal)
    /// The optimal green for text (tags, kickers): darker in Light so it
    /// reaches 4.5:1 on its tint; the same as `statusOptimal` in Dark.
    static let statusOptimalText = Color(.vessStatusOptimalText)
    static let statusSufficient = Color(.vessStatusSufficient)
    static let statusPoor = Color(.vessStatusPoor)
    /// Soon: dots and lines.
    static let warning = Color(.vessWarning)
    /// Soon: text on `warningTint`.
    static let warningText = Color(.vessWarningText)
    static let warningTint = Color(.vessWarningTint)
    /// Now (expires today, expired): text on `criticalTint`. Use rarely.
    static let criticalText = Color(.vessCriticalText)
    static let criticalTint = Color(.vessCriticalTint)

    // MARK: Charts

    static let chartTrack = Color(.vessChartTrack)
    static let chartGuide = Color(.vessChartGuide)
    static let chartMuted = Color(.vessChartMuted)

    // MARK: Atmosphere
    // Top-of-screen tint behind a metric's detail screen.

    static let atmosNeutral = Color(.vessAtmosNeutral)
    static let atmosEnergy = Color(.vessAtmosEnergy)
    static let atmosWater = Color(.vessAtmosWater)
    static let atmosActivity = Color(.vessAtmosActivity)
    static let atmosProtein = Color(.vessAtmosProtein)
    static let atmosCycle = Color(.vessAtmosCycle)

    // MARK: Tints, strokes, materials

    static let materialTabbar = Color(.vessMaterialTabbar)
    static let tintOptimal = Color(.vessTintOptimal)
    static let tintPoor = Color(.vessTintPoor)
    static let tintLink = Color(.vessAccentSoft)
    static let tintWater = Color(.vessTintWater)
    static let tintRange = Color(.vessTintRange)
    /// The cycle hue at 16 % (Dark) or 12 % (Light): estimated days.
    static let tintCycle = Color(.vessTintCycle)
    static let strokeLink = Color(.vessStrokeLink)
    static let strokeWater = Color(.vessStrokeWater)
    static let surfaceGlass = Color(.vessSurfaceGlass)
    static let scrimNav = Color(.vessScrimNav)
    static let scrimComposer = Color(.vessScrimComposer)

    /// The InsightCard's 1 pt border. The only gradient in the app.
    static let insightBorder = LinearGradient(
        stops: [
            .init(color: Color(.vessInsightBorderStart), location: 0),
            .init(color: Color(.vessInsightBorderMid), location: 0.55),
            .init(color: Color(.vessInsightBorderEnd), location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// Which metric a view is about. Drives its hue and screen atmosphere.
enum VESSMetricKind {
    case fuel, energy, protein, carbs, fat, water, activity, cycle

    var tint: Color {
        switch self {
        case .fuel: VESSColor.text   // The Fuel ring is neutral.
        case .energy: VESSColor.calories
        case .protein: VESSColor.protein
        case .carbs: VESSColor.carbs
        case .fat: VESSColor.fat
        case .water: VESSColor.water
        case .activity: VESSColor.activity
        case .cycle: VESSColor.cycle
        }
    }

    var atmosphere: Color {
        switch self {
        case .fuel, .carbs, .fat: VESSColor.atmosNeutral
        case .energy: VESSColor.atmosEnergy
        case .protein: VESSColor.atmosProtein
        case .water: VESSColor.atmosWater
        case .activity: VESSColor.atmosActivity
        case .cycle: VESSColor.atmosCycle
        }
    }
}
