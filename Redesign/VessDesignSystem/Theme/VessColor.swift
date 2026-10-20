//  VessColor.swift
//  VESS design tokens: colour.
//  Source of truth: Figma file "VESS — Redesign (Dark)", collections
//  "VESS Color · Dark" and "VESS Color · Light" (identical token names).
//
//  Rules
//  - Colour is DATA ONLY. Each metric owns one hue (metric*). Everything else is greyscale.
//  - The app is dark-first. Unspecified / unknown appearance resolves to Dark.
//  - Never use raw hex in views. Add a token here instead.

import SwiftUI
import UIKit

enum VessColor {
    // MARK: Background
    static let bgBase       = Color(dark: 0x0B0C0D, light: 0xF6F6F3)
    static let bgElevated   = Color(dark: 0x16181A, light: 0xFFFFFF)
    static let bgSunken     = Color(dark: 0x111314, light: 0xEDEDE8)
    static let bgRaised     = Color(dark: 0x1E2123, light: 0xF1F1EC)

    // MARK: Border
    static let borderHairline = Color(dark: 0xFFFFFF, darkAlpha: 0.07, light: 0x000000, lightAlpha: 0.08)
    static let borderStrong   = Color(dark: 0xFFFFFF, darkAlpha: 0.14, light: 0x000000, lightAlpha: 0.16)

    // MARK: Text
    static let textPrimary   = Color(dark: 0xEDEEEA, light: 0x141514)
    static let textSecondary = Color(dark: 0x9A9E9A, light: 0x5C605C)
    static let textTertiary  = Color(dark: 0x5E625F, light: 0x9C9F9A)
    static let textInverse   = Color(dark: 0x0B0C0D, light: 0xFFFFFF)

    // MARK: Accent
    /// Links and tracked-caps CTAs only (e.g. "BREAK DOWN MY DAY →").
    static let accentLink = Color(dark: 0x9AA5FF, light: 0x4B57CF)
    /// Primary button fill, selected chip / day pill.
    static let accentFill = Color(dark: 0xEDEEEA, light: 0x141514)

    // MARK: Metric hues (data only)
    static let metricEnergy   = Color(dark: 0xE2A55C, light: 0xB5762A)
    static let metricProtein  = Color(dark: 0xA897D8, light: 0x6F5CA6)
    static let metricCarbs    = Color(dark: 0xD5BD6C, light: 0x9E8228)
    static let metricFat      = Color(dark: 0x7DB4B0, light: 0x3F807C)
    static let metricWater    = Color(dark: 0x6EA8D8, light: 0x3574AA)
    static let metricActivity = Color(dark: 0x8CC68B, light: 0x47884A)

    // MARK: Status
    static let statusOptimal    = Color(dark: 0x5CD39B, light: 0x23965F)
    static let statusSufficient = Color(dark: 0x8B908C, light: 0xA3A6A1)
    static let statusPoor       = Color(dark: 0xF0A24B, light: 0xC2741B)

    // MARK: Chart
    static let chartTrack = Color(dark: 0xFFFFFF, darkAlpha: 0.08, light: 0x000000, lightAlpha: 0.07)
    static let chartGuide = Color(dark: 0xFFFFFF, darkAlpha: 0.06, light: 0x000000, lightAlpha: 0.06)
    static let chartMuted = Color(dark: 0x9A9E9A, darkAlpha: 0.45, light: 0x5C605C, lightAlpha: 0.35)

    // MARK: Atmosphere (top-of-screen tint, fades to bgBase over ~440pt)
    static let atmosNeutral  = Color(dark: 0x1C242C, light: 0xE6EBEF)
    static let atmosEnergy   = Color(dark: 0x2A231D, light: 0xF2EADF)
    static let atmosWater    = Color(dark: 0x16222D, light: 0xE1EBF3)
    static let atmosActivity = Color(dark: 0x16231B, light: 0xE2EDE1)
    static let atmosProtein  = Color(dark: 0x211D2B, light: 0xECE8F3)

    // MARK: Materials, tints, scrims
    static let materialTabbar = Color(dark: 0x1C1E20, darkAlpha: 0.84, light: 0xFFFFFF, lightAlpha: 0.88)
    static let tintOptimal  = Color(dark: 0x5CD39B, darkAlpha: 0.14, light: 0x23965F, lightAlpha: 0.12)
    static let tintPoor     = Color(dark: 0xF0A24B, darkAlpha: 0.14, light: 0xC2741B, lightAlpha: 0.12)
    static let tintLink     = Color(dark: 0x9AA5FF, darkAlpha: 0.15, light: 0x4B57CF, lightAlpha: 0.10)
    static let tintWater    = Color(dark: 0x6EA8D8, darkAlpha: 0.16, light: 0x3574AA, lightAlpha: 0.12)
    static let tintRange    = Color(dark: 0x5CD39B, darkAlpha: 0.07, light: 0x23965F, lightAlpha: 0.07)
    static let strokeLink   = Color(dark: 0x9AA5FF, darkAlpha: 0.55, light: 0x4B57CF, lightAlpha: 0.50)
    static let strokeWater  = Color(dark: 0x6EA8D8, darkAlpha: 0.70, light: 0x3574AA, lightAlpha: 0.60)
    static let surfaceGlass = Color(dark: 0x16181A, darkAlpha: 0.55, light: 0xFFFFFF, lightAlpha: 0.70)
    static let scrimNav      = Color(dark: 0x0B0C0D, darkAlpha: 0.55, light: 0xFFFFFF, lightAlpha: 0.70)
    static let scrimComposer = Color(dark: 0x0B0C0D, darkAlpha: 0.92, light: 0xF6F6F3, lightAlpha: 0.92)

    /// Gradient used only for the 1pt InsightCard border (decorative, not a token in Figma).
    static let insightBorder = LinearGradient(
        stops: [
            .init(color: Color(red: 0.60, green: 0.65, blue: 1.00).opacity(0.55), location: 0),
            .init(color: Color(red: 0.55, green: 0.55, blue: 0.75).opacity(0.18), location: 0.55),
            .init(color: Color(red: 0.36, green: 0.78, blue: 0.70).opacity(0.45), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)
}

/// Which metric a view is about. Drives hue + atmosphere.
enum VessMetric {
    case fuel, energy, protein, carbs, fat, water, activity

    var tint: Color {
        switch self {
        case .fuel:     VessColor.textPrimary   // Fuel ring is neutral white (Oura-style)
        case .energy:   VessColor.metricEnergy
        case .protein:  VessColor.metricProtein
        case .carbs:    VessColor.metricCarbs
        case .fat:      VessColor.metricFat
        case .water:    VessColor.metricWater
        case .activity: VessColor.metricActivity
        }
    }

    var atmosphere: Color {
        switch self {
        case .fuel, .carbs, .fat: VessColor.atmosNeutral
        case .energy:   VessColor.atmosEnergy
        case .protein:  VessColor.atmosProtein
        case .water:    VessColor.atmosWater
        case .activity: VessColor.atmosActivity
        }
    }
}

// MARK: - Dynamic colour helper

extension Color {
    /// Dark-first dynamic colour. `.light` trait → light value, everything else → dark value.
    init(dark: UInt32, darkAlpha: Double = 1, light: UInt32, lightAlpha: Double = 1) {
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor(hex: light, alpha: lightAlpha)
                : UIColor(hex: dark, alpha: darkAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: CGFloat(alpha))
    }
}
