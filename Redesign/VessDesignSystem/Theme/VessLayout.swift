//  VessLayout.swift
//  VESS design tokens: spacing, radii, sizes, motion.

import SwiftUI

enum VessSpace {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s40: CGFloat = 40

    /// Horizontal screen margin.
    static let screenMargin: CGFloat = 20
    /// Vertical gap between major sections on scroll screens (Today uses 36).
    static let section: CGFloat = 32
}

enum VessRadius {
    static let sm: CGFloat = 8    // legend chip, small tags (Tag uses 5)
    static let md: CGFloat = 12   // impact rows, quick-add tiles (14)
    static let lg: CGFloat = 16   // insight card, featured recipe, embedded cards
    static let sheet: CGFloat = 32
}

enum VessSize {
    static let heroRing: CGFloat = 248
    static let stripRing: CGFloat = 52
    static let rowHeight: CGFloat = 56          // MetricRow / StatusRow
    static let buttonHeight: CGFloat = 52       // full-width capsule
    static let iconButton: CGFloat = 40
    static let tabBarHeight: CGFloat = 62
    static let tabCapsuleWidth: CGFloat = 290
    static let addButton: CGFloat = 62
    static let rowIcon: CGFloat = 20
    static let minTarget: CGFloat = 44
}

/// Ring stroke = 9.5% of the RADIUS (≈ 4.75% of diameter). Hero 248pt → ~11.8pt. Strip 52pt → ~3.1pt.
enum VessRing {
    static func lineWidth(diameter: CGFloat, innerRadiusRatio: CGFloat = 0.905) -> CGFloat {
        diameter / 2 * (1 - innerRadiusRatio)
    }
}

enum VessMotion {
    static let ringSweep = Animation.easeOut(duration: 0.8)
    static let rowStagger: Double = 0.04       // seconds between breakdown rows
    static let countUp = Animation.easeOut(duration: 0.8)
    static let sheet = Animation.spring(response: 0.38, dampingFraction: 0.86)
}
