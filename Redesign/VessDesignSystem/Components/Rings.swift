//  Rings.swift
//  ScoreRing (hero) and MetricStripItem (Oura-style score strip).
//  Figma: Foundations › Components › ScoreRing, MetricStripItem.
//  Ring: flat (butt) caps, starts at 12 o'clock, clockwise. Track = chart/track.

import SwiftUI

struct RingShape: View {
    var progress: Double          // 0...1
    var tint: Color
    var lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(VessColor.chartTrack, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Hero score ring. Value in Display/Hero, optional unit in Title/L, caps label, caption sublabel.
struct ScoreRing: View {
    var value: String                 // "78", "6,420", "—"
    var unit: String? = nil           // "%", "/30"
    var label: String                 // "Fuel"
    var sublabel: String? = nil       // "3 of 4 meals logged"
    var progress: Double              // 0...1; 0 hides the arc
    var metric: VessMetric = .fuel
    var diameter: CGFloat = VessSize.heroRing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            RingShape(progress: shown, tint: metric.tint,
                      lineWidth: VessRing.lineWidth(diameter: diameter))
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .vessText(value.count > 3 ? .displayL : .displayHero)
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit).vessText(.titleL).foregroundStyle(VessColor.textSecondary)
                    }
                }
                .foregroundStyle(VessColor.textPrimary)
                Text(label).vessText(.labelCaps).foregroundStyle(VessColor.textPrimary)
                if let sublabel {
                    Text(sublabel).vessText(.caption).foregroundStyle(VessColor.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { shown = progress } else { withAnimation(VessMotion.ringSweep) { shown = progress } }
        }
        .onChange(of: progress) { _, new in withAnimation(reduceMotion ? nil : VessMotion.ringSweep) { shown = new } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)\(unit ?? "")")
        .accessibilityValue(sublabel ?? "")
    }
}

/// Small ring + label, used in the top metric strip on Today (Fuel · Energy · Protein · Water · Steps).
struct MetricStripItem: View {
    var value: String
    var label: String
    var progress: Double
    var metric: VessMetric

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RingShape(progress: progress, tint: metric.tint,
                          lineWidth: VessRing.lineWidth(diameter: VessSize.stripRing, innerRadiusRatio: 0.88))
                Text(value).vessText(.numberS).foregroundStyle(VessColor.textPrimary)
            }
            .frame(width: VessSize.stripRing, height: VessSize.stripRing)
            Text(label).vessText(.caption).foregroundStyle(VessColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Rings") {
    VStack(spacing: 32) {
        HStack {
            MetricStripItem(value: "78", label: "Fuel", progress: 0.78, metric: .fuel)
            MetricStripItem(value: "77", label: "Energy", progress: 0.77, metric: .energy)
            MetricStripItem(value: "77", label: "Protein", progress: 0.77, metric: .protein)
            MetricStripItem(value: "73", label: "Water", progress: 0.73, metric: .water)
            MetricStripItem(value: "80", label: "Steps", progress: 0.80, metric: .activity)
        }
        ScoreRing(value: "78", label: "Fuel", sublabel: "3 of 4 meals logged", progress: 0.78)
    }
    .padding().background(VessColor.bgBase).preferredColorScheme(.dark)
}
