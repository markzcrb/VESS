import SwiftUI

/// The four haptics VESS uses, and nothing else (Redesign/docs/MOTION.md):
/// - `add`: a soft impact when the + opens the Add sheet;
/// - `selection`: chips, tabs, segments, cards and calendar days;
/// - `success`: something saved or added;
/// - `warning`: something deleted.
enum VESSHaptic {
    case add, selection, success, warning

    var feedback: SensoryFeedback {
        switch self {
        case .add: .impact(flexibility: .soft)
        case .selection: .selection
        case .success: .success
        case .warning: .warning
        }
    }
}

/// Plays haptics for actions whose view may go away at once (a sheet that
/// closes on Save or Delete). The app root plays them, so they're never lost.
@Observable
final class VESSHaptics {
    /// Nobody plays this one: the environment's default, for previews.
    static let unplayed = VESSHaptics()

    private(set) var addCount = 0
    private(set) var successCount = 0
    private(set) var warningCount = 0

    func play(_ haptic: VESSHaptic) {
        switch haptic {
        case .add: addCount += 1
        case .success: successCount += 1
        case .warning: warningCount += 1
        // Selection follows a view's own state: use `vessHaptic(.selection, trigger:)`.
        case .selection: break
        }
    }
}

extension EnvironmentValues {
    /// Previews get an instance nobody plays; the app root injects the real one.
    @Entry var vessHaptics: VESSHaptics = .unplayed
}

extension View {
    /// A haptic when `trigger` changes.
    func vessHaptic<T: Equatable>(_ haptic: VESSHaptic, trigger: T) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }

    /// A haptic when `trigger` changes and `condition(old, new)` holds.
    func vessHaptic<T: Equatable>(_ haptic: VESSHaptic, trigger: T, condition: @escaping (T, T) -> Bool) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger, condition: condition)
    }

    /// At the app root: plays what `VESSHaptics` is asked to play.
    func vessHapticsHost(_ haptics: VESSHaptics) -> some View {
        environment(\.vessHaptics, haptics)
            .vessHaptic(.add, trigger: haptics.addCount)
            .vessHaptic(.success, trigger: haptics.successCount)
            .vessHaptic(.warning, trigger: haptics.warningCount)
    }
}
