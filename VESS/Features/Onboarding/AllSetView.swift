import SwiftUI

/// B03, once, right after onboarding: the targets that were set, then
/// Open Today, or Connect Apple Health first (hidden once Health is
/// connected or where there's no Health).
struct AllSetView: View {
    let profile: UserProfile
    let showsConnectHealth: Bool
    let onOpenToday: () -> Void
    let onConnectHealth: () -> Void

    var body: some View {
        BrandScreenLayout {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text("All set")
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    Text(welcome)
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your daily targets are ready. They're a starting point, not a rule.")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .padding(.top, VESSSpacing.xxs)
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    VESSRowGroup {
                        ForEach(Array(AllSetTargets.rows(for: profile).enumerated()), id: \.offset) { _, row in
                            VESSRow(title: title(row)) {
                                Text(verbatim: value(row))
                                    .vessTextStyle(.numberRow)
                                    .foregroundStyle(VESSColor.text)
                            }
                            .frame(minHeight: VESSSize.rowHeight)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .vessHairlineBottom()
                    Text("Change them anytime in You › Goals.")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, VESSSpacing.huge)
        } bottom: {
            VStack(spacing: VESSSpacing.xs) {
                Button("Open Today", action: onOpenToday)
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("allSet.openToday")
                if showsConnectHealth {
                    Button("Connect Apple Health first", action: onConnectHealth)
                        .buttonStyle(.brandText)
                        .accessibilityIdentifier("allSet.connectHealth")
                }
            }
        }
        .background { BrandBackground() }
    }

    private var welcome: LocalizedStringResource {
        if let name = AllSetTargets.firstName(profile.name) {
            return "Welcome, \(name)."
        }
        return "Welcome."
    }

    private func title(_ row: AllSetTargets.Kind) -> Text {
        switch row {
        case .energy: Text("Energy")
        case .protein: Text("Protein")
        case .water: Text("Water")
        case .steps: Text("Steps")
        case .sleep: Text("Sleep")
        }
    }

    private func value(_ row: AllSetTargets.Kind) -> String {
        let space = VESSFormat.unitSpace
        switch row {
        case .energy(let kcal): return VESSFormat.calories(kcal) + space + String(localized: "kcal")
        case .protein(let grams): return VESSFormat.grams(grams) + space + "g"
        case .water(let milliliters): return VESSFormat.liters(fromMilliliters: milliliters) + space + "L"
        case .steps(let steps): return VESSFormat.steps(Double(steps))
        case .sleep(let minutes):
            // "8 h" for whole hours, "7 h 30" otherwise.
            return minutes % 60 == 0 ? "\(minutes / 60)\(space)h" : VESSFormat.duration(minutes: Double(minutes))
        }
    }
}

#if DEBUG
#Preview("B03 Light") {
    if let profile = LocalStore.preview().profile {
        AllSetView(profile: profile, showsConnectHealth: true, onOpenToday: {}, onConnectHealth: {})
            .preferredColorScheme(.light)
    }
}

#Preview("B03 Dark") {
    if let profile = LocalStore.preview().profile {
        AllSetView(profile: profile, showsConnectHealth: true, onOpenToday: {}, onConnectHealth: {})
            .preferredColorScheme(.dark)
    }
}
#endif
