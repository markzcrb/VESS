//  Controls.swift
//  VessButtonStyle, IconButton, Chip, VessTag, VessSegmented, VessTabBar, nav title, atmosphere.

import SwiftUI

// MARK: - Buttons

enum VessButtonKind { case primary, secondary, quiet }

/// Full-width capsule button, 52pt tall. Primary = accent/fill + text/inverse.
struct VessButtonStyle: ButtonStyle {
    var kind: VessButtonKind = .primary
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vessText(.bodyMStrong)
            .foregroundStyle(kind == .primary ? VessColor.textInverse : kind == .quiet ? VessColor.accentLink : VessColor.textPrimary)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: VessSize.buttonHeight)
            .padding(.horizontal, fullWidth ? 0 : 20)
            .background {
                switch kind {
                case .primary:   Capsule().fill(VessColor.accentFill)
                case .secondary: Capsule().fill(VessColor.bgRaised).overlay(Capsule().strokeBorder(VessColor.borderHairline))
                case .quiet:     Color.clear
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed)
    }
}

extension ButtonStyle where Self == VessButtonStyle {
    static var vessPrimary: VessButtonStyle { .init(kind: .primary) }
    static var vessSecondary: VessButtonStyle { .init(kind: .secondary) }
    static var vessQuiet: VessButtonStyle { .init(kind: .quiet) }
}

struct IconButton: View {
    var systemImage: String
    var filled = false                 // accent fill (e.g. "added" check)
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 17, weight: .medium))
                .foregroundStyle(filled ? VessColor.textInverse : VessColor.textPrimary)
                .frame(width: VessSize.iconButton, height: VessSize.iconButton)
                .background(Circle().fill(filled ? VessColor.accentFill : VessColor.bgRaised))
                .overlay(Circle().strokeBorder(VessColor.borderHairline))
                .frame(minWidth: VessSize.minTarget, minHeight: VessSize.minTarget)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chip

struct Chip: View {
    var label: String
    var selected = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(label).vessText(.bodyS)
                .foregroundStyle(selected ? VessColor.textInverse : VessColor.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(selected ? VessColor.accentFill : VessColor.bgRaised))
                .overlay(Capsule().strokeBorder(selected ? Color.clear : VessColor.borderHairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Tag

enum VessTagTone { case neutral, positive, warning, accent }

/// "Recorded", "Entered", "In pantry", "Missing", "Use by Thu", "New".
struct VessTag: View {
    var label: String
    var tone: VessTagTone = .neutral

    var body: some View {
        let (bg, fg): (Color, Color) = switch tone {
        case .neutral:  (VessColor.bgRaised, VessColor.textSecondary)
        case .positive: (VessColor.tintOptimal, VessColor.statusOptimal)
        case .warning:  (VessColor.tintPoor, VessColor.statusPoor)
        case .accent:   (VessColor.tintLink, VessColor.accentLink)
        }
        Text(label).vessText(.labelCapsS).foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(bg, in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Segmented control

struct VessSegmented<T: Hashable>: View {
    @Binding var selection: T
    var options: [(T, String)]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option in
                let value = option.0, title = option.1
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = value }
                } label: {
                    Text(title).vessText(.bodyS)
                        .foregroundStyle(selection == value ? VessColor.textPrimary : VessColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background {
                            if selection == value {
                                Capsule().fill(VessColor.borderStrong).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(VessColor.bgRaised))
    }
}

// MARK: - Tab bar  (Oura-style floating capsule + separate add button)

enum VessTab: String, CaseIterable, Identifiable {
    case today = "Today", nutrition = "Nutrition", plan = "Plan", you = "You"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .today: "sun.max"; case .nutrition: "fork.knife"; case .plan: "calendar"; case .you: "person" }
    }
}

struct VessTabBar: View {
    @Binding var selection: VessTab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(VessTab.allCases) { tab in
                    let on = tab == selection
                    Button { selection = tab } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol).font(.system(size: 19, weight: .regular))
                            Text(tab.rawValue).vessText(.caption)
                        }
                        .foregroundStyle(on ? VessColor.textPrimary : VessColor.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background { if on { Capsule().fill(VessColor.borderHairline) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityShowsLargeContentViewer { Label(tab.rawValue, systemImage: tab.symbol) }
                }
            }
            .padding(5)
            .frame(height: VessSize.tabBarHeight)
            .background(.ultraThinMaterial, in: Capsule())
            .background(VessColor.materialTabbar, in: Capsule())
            .overlay(Capsule().strokeBorder(VessColor.borderHairline))

            Button(action: onAdd) {
                Image(systemName: "plus").font(.system(size: 22, weight: .regular))
                    .foregroundStyle(VessColor.textPrimary)
                    .frame(width: VessSize.addButton, height: VessSize.addButton)
                    .background(.ultraThinMaterial, in: Circle())
                    .background(VessColor.materialTabbar, in: Circle())
                    .overlay(Circle().strokeBorder(VessColor.borderHairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add")
        }
        .padding(.horizontal, VessSpace.screenMargin)
    }
}

// MARK: - Navigation title (centered tracked caps) & atmosphere

extension View {
    /// Detail-screen nav: centered TRACKED CAPS title (+ optional caption subtitle).
    func vessNavigationTitle(_ title: String, subtitle: String? = nil) -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(title).vessText(.labelCaps).foregroundStyle(VessColor.textPrimary)
                        if let subtitle { Text(subtitle).vessText(.caption).foregroundStyle(VessColor.textSecondary) }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Screen background: bgBase with a metric-tinted atmosphere fading out over the top 440pt.
    func vessScreenBackground(_ metric: VessMetric? = .fuel) -> some View {
        background(alignment: .top) {
            ZStack(alignment: .top) {
                VessColor.bgBase
                if let metric {
                    LinearGradient(colors: [metric.atmosphere, metric.atmosphere.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 440)
                }
            }
            .ignoresSafeArea()
        }
    }
}
