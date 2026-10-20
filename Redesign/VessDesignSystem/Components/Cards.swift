//  Cards.swift
//  InsightCard, MacroBar, ImpactRow.

import SwiftUI

// MARK: - InsightCard

/// Plain-language insight + tracked-caps CTA. 1pt gradient border; shimmers once on appear.
struct InsightCard: View {
    var kicker: String? = nil           // e.g. "Steady" (status/optimal)
    var text: String
    var cta: String? = "Break down my day"
    var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let kicker { Text(kicker).vessText(.labelCapsS).foregroundStyle(VessColor.statusOptimal) }
            Text(text).vessText(.bodyM).foregroundStyle(VessColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let cta {
                Button(action: onTap) {
                    HStack(spacing: 6) {
                        Text(cta).vessText(.labelCapsLink)
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(VessColor.accentLink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 18).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VessColor.surfaceGlass, in: RoundedRectangle(cornerRadius: VessRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: VessRadius.lg)
                .strokeBorder(VessColor.insightBorder, lineWidth: 1)
                .opacity(shimmer ? 1 : 0.85)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).delay(0.9)) { shimmer = true }
        }
    }
}

// MARK: - MacroBar

/// Linear macro progress. Grey = already logged today; metric hue = this item (or today's total).
struct MacroBar: View {
    var name: String          // "Protein"
    var value: String         // "108" or "+31 g"
    var target: String        // "/ 140 g" or "→ 139 / 140 g"
    var logged: Double = 0    // 0...1 of target, drawn in text/tertiary
    var adding: Double        // 0...1 of target, drawn in metric hue after `logged`
    var metric: VessMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).vessText(.labelCaps).foregroundStyle(VessColor.textPrimary)
                Spacer()
                Text(value).vessText(.numberS).foregroundStyle(VessColor.textPrimary)
                Text(target).vessText(.caption).foregroundStyle(VessColor.textTertiary)
            }
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(VessColor.chartTrack)
                    HStack(spacing: 0) {
                        Rectangle().fill(VessColor.textTertiary).frame(width: w * clamp(logged))
                        Rectangle().fill(metric.tint).frame(width: w * clamp(adding, max: 1 - clamp(logged)))
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
    }

    private func clamp(_ v: Double, max m: Double = 1) -> Double { Swift.max(0, Swift.min(m, v)) }
}

// MARK: - ImpactRow  (Insights: HURTS ← 0 → HELPS)

struct ImpactRow: View {
    var label: String
    var impactPercent: Int        // e.g. +24, -11
    var maxPercent: Int = 26      // full half-width
    var isNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if isNew {
                    Text("New").vessText(.labelCapsS).foregroundStyle(VessColor.accentLink)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(VessColor.tintLink, in: RoundedRectangle(cornerRadius: 4))
                }
                Text(label).vessText(.labelCaps).foregroundStyle(VessColor.textPrimary)
                Spacer()
                Text(impactPercent >= 0 ? "+\(impactPercent)%" : "−\(abs(impactPercent))%")
                    .vessText(.numberS)
                    .foregroundStyle(impactPercent >= 0 ? VessColor.statusOptimal : VessColor.statusPoor)
            }
            GeometryReader { g in
                let half = g.size.width / 2
                let len = half * min(1, Double(abs(impactPercent)) / Double(maxPercent))
                ZStack(alignment: .leading) {
                    Capsule().fill(VessColor.chartTrack).frame(height: 6)
                    Capsule()
                        .fill(impactPercent >= 0 ? VessColor.statusOptimal : VessColor.statusPoor)
                        .frame(width: max(6, len), height: 6)
                        .offset(x: impactPercent >= 0 ? half : half - max(6, len))
                    Circle().fill(VessColor.textPrimary).frame(width: 8, height: 8).offset(x: half - 4)
                }
            }
            .frame(height: 8)
        }
        .padding(.top, 14).padding(.bottom, 16).padding(.horizontal, 16)
        .background(VessColor.bgElevated, in: RoundedRectangle(cornerRadius: VessRadius.md))
        .overlay { if isNew { RoundedRectangle(cornerRadius: VessRadius.md).strokeBorder(VessColor.strokeLink, lineWidth: 1) } }
        .accessibilityElement(children: .combine)
    }
}
