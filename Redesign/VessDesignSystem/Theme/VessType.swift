//  VessType.swift
//  VESS design tokens: typography.
//
//  - SF Pro everywhere (system font). Numbers use monospaced digits so columns line up.
//  - Editorial styles use New York = `.serif` design. (Figma shows Newsreader only
//    because New York is not available there. Do NOT bundle Newsreader.)
//  - Tracking values from Figma are percentages of font size; converted here to points.
//  - Every style scales with Dynamic Type relative to a system text style (AX3/AX5 designs exist).
//  - Use at most ONE editorial line per screen.

import SwiftUI

enum VessTextStyle: CaseIterable {
    case displayHero, displayL, displayM
    case titleL
    case numberRow, numberS
    case bodyM, bodyMStrong, bodyS
    case caption
    case labelCaps, labelCapsS, labelCapsLink
    case editorialL, editorialM

    struct Spec {
        let size: CGFloat
        let weight: Font.Weight
        let trackingPercent: CGFloat
        let lineHeight: CGFloat?      // nil = default line height
        let relativeTo: Font.TextStyle
        let serif: Bool
        let uppercase: Bool
        let numeric: Bool             // monospaced digits
    }

    var spec: Spec {
        switch self {
        case .displayHero:   Spec(size: 76,   weight: .bold,     trackingPercent: -3,   lineHeight: nil, relativeTo: .largeTitle, serif: false, uppercase: false, numeric: true)
        case .displayL:      Spec(size: 48,   weight: .bold,     trackingPercent: -2,   lineHeight: nil, relativeTo: .largeTitle, serif: false, uppercase: false, numeric: true)
        case .displayM:      Spec(size: 32,   weight: .semibold, trackingPercent: -1.5, lineHeight: nil, relativeTo: .title,      serif: false, uppercase: false, numeric: true)
        case .titleL:        Spec(size: 22,   weight: .semibold, trackingPercent: -0.5, lineHeight: nil, relativeTo: .title2,     serif: false, uppercase: false, numeric: false)
        case .numberRow:     Spec(size: 19,   weight: .semibold, trackingPercent: -0.5, lineHeight: nil, relativeTo: .title3,     serif: false, uppercase: false, numeric: true)
        case .numberS:       Spec(size: 15,   weight: .semibold, trackingPercent: -0.2, lineHeight: nil, relativeTo: .subheadline, serif: false, uppercase: false, numeric: true)
        case .bodyM:         Spec(size: 16,   weight: .regular,  trackingPercent: -0.2, lineHeight: 22,  relativeTo: .body,       serif: false, uppercase: false, numeric: false)
        case .bodyMStrong:   Spec(size: 16,   weight: .semibold, trackingPercent: -0.2, lineHeight: 22,  relativeTo: .body,       serif: false, uppercase: false, numeric: false)
        case .bodyS:         Spec(size: 14,   weight: .regular,  trackingPercent: -0.1, lineHeight: 19,  relativeTo: .subheadline, serif: false, uppercase: false, numeric: false)
        case .caption:       Spec(size: 12,   weight: .regular,  trackingPercent: 0,    lineHeight: 16,  relativeTo: .caption,    serif: false, uppercase: false, numeric: true)
        case .labelCaps:     Spec(size: 12,   weight: .semibold, trackingPercent: 9,    lineHeight: nil, relativeTo: .caption,    serif: false, uppercase: true,  numeric: false)
        case .labelCapsS:    Spec(size: 10.5, weight: .semibold, trackingPercent: 10,   lineHeight: nil, relativeTo: .caption2,   serif: false, uppercase: true,  numeric: false)
        case .labelCapsLink: Spec(size: 12,   weight: .bold,     trackingPercent: 10,   lineHeight: nil, relativeTo: .caption,    serif: false, uppercase: true,  numeric: false)
        case .editorialL:    Spec(size: 30,   weight: .regular,  trackingPercent: -1,   lineHeight: 34,  relativeTo: .title,      serif: true,  uppercase: false, numeric: false)
        case .editorialM:    Spec(size: 24,   weight: .regular,  trackingPercent: -0.5, lineHeight: 29,  relativeTo: .title2,     serif: true,  uppercase: false, numeric: false)
        }
    }
}

struct VessTextModifier: ViewModifier {
    let style: VessTextStyle
    @ScaledMetric private var size: CGFloat

    init(_ style: VessTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.spec.size, relativeTo: style.spec.relativeTo)
    }

    func body(content: Content) -> some View {
        let s = style.spec
        let scale = size / s.size
        var font = Font.system(size: size, weight: s.weight, design: s.serif ? .serif : .default)
        if s.numeric { font = font.monospacedDigit() }
        let extraLeading = s.lineHeight.map { max(0, ($0 * scale) - size * 1.19) } ?? 0
        return content
            .font(font)
            .tracking(size * s.trackingPercent / 100)
            .lineSpacing(extraLeading)
            .textCase(s.uppercase ? .uppercase : nil)
    }
}

extension View {
    /// Apply a VESS text style: `Text("Fuel").vessText(.labelCaps)`
    func vessText(_ style: VessTextStyle) -> some View { modifier(VessTextModifier(style)) }
}
