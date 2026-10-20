import SwiftUI

/// The Vessel Line: VESS's thin progress indicator.
///
/// Continuous by default. Pass `segments` for countable progress such as
/// glasses of water. When `value` exceeds 1 the line stays full and a small
/// marker shows where the target was. Over target is never shown in red.
///
/// The line is decorative for VoiceOver: the parent view speaks the value.
struct VESSVesselLine: View {
    /// Progress toward the target; 1 means the target is reached.
    let value: Double
    var tint: Color = VESSColor.accent
    var segments: Int?

    @ScaledMetric(relativeTo: .body) private var thickness: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private var displayed: Double {
        hasAppeared || reduceMotion ? max(value, 0) : 0
    }

    var body: some View {
        Group {
            if let segments, segments > 0 {
                segmented(count: segments)
            } else {
                continuous
            }
        }
        .frame(height: thickness)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.6)) {
                hasAppeared = true
            }
        }
    }

    private var continuous: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(VESSColor.chartTrack)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(displayed, 1))
            }
            .overlay(alignment: .trailing) {
                if value > 1 {
                    // Target marker when over target.
                    Capsule()
                        .fill(VESSColor.text)
                        .frame(width: 1.5, height: thickness * 3)
                }
            }
        }
    }

    private func segmented(count: Int) -> some View {
        let filled = Int((min(displayed, 1) * Double(count)).rounded())
        return HStack(spacing: thickness) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? tint : VESSColor.chartTrack)
            }
        }
    }
}
