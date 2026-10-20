//  Rows.swift
//  MetricRow, StatusRow, LegendChip, MealRow, ListRow, SectionHeader.
//  Rows are hairline-separated lists, never one card per row.

import SwiftUI

// MARK: - Hairline

struct Hairline: View {
    var body: some View { Rectangle().fill(VessColor.borderHairline).frame(height: 1) }
}

extension View {
    func hairlineBottom() -> some View { overlay(alignment: .bottom) { Hairline() } }
}

// MARK: - Delta triangle

enum VessTrend { case up, down, flat }

struct DeltaMark: View {
    var trend: VessTrend
    var body: some View {
        Group {
            switch trend {
            case .up:   Triangle().fill(VessColor.statusOptimal)
            case .down: Triangle().fill(VessColor.statusPoor).rotationEffect(.degrees(180))
            case .flat: Circle().fill(VessColor.statusSufficient).padding(2)
            }
        }
        .frame(width: 8, height: 7)
        .accessibilityLabel(trend == .up ? "Up" : trend == .down ? "Down" : "No change")
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath() }
    }
}

// MARK: - MetricRow  (WHOOP breakdown row)

/// icon · TRACKED LABEL · value · delta vs prior 30 days. Height 56, hairline bottom.
struct MetricRow: View {
    var systemImage: String
    var label: String
    var value: String
    var trend: VessTrend?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).font(.system(size: 17, weight: .regular))
                .foregroundStyle(VessColor.textSecondary).frame(width: VessSize.rowIcon)
            Text(label).vessText(.labelCaps).foregroundStyle(VessColor.textPrimary)
            Spacer(minLength: 8)
            Text(value).vessText(.numberRow).foregroundStyle(VessColor.textPrimary)
            if let trend { DeltaMark(trend: trend) }
        }
        .frame(minHeight: VessSize.rowHeight)
        .hairlineBottom()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - StatusRow  (Poor / Sufficient / Optimal)

enum VessLevel: Int { case poor = 0, sufficient = 1, optimal = 2
    var color: Color { switch self { case .poor: VessColor.statusPoor; case .sufficient: VessColor.textSecondary; case .optimal: VessColor.statusOptimal } }
    var name: String { switch self { case .poor: "Poor"; case .sufficient: "Sufficient"; case .optimal: "Optimal" } }
}

struct StatusRow: View {
    var systemImage: String
    var label: String
    var value: String
    var level: VessLevel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).font(.system(size: 17)).foregroundStyle(VessColor.textSecondary).frame(width: VessSize.rowIcon)
            Text(label).vessText(.labelCaps).foregroundStyle(VessColor.textPrimary)
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Capsule().fill(i == level.rawValue ? level.color : VessColor.chartTrack).frame(width: 22, height: 3)
                }
            }
            Text(value).vessText(.numberRow).foregroundStyle(VessColor.textPrimary)
                .frame(minWidth: 58, alignment: .trailing)
        }
        .frame(minHeight: VessSize.rowHeight)
        .hairlineBottom()
        .accessibilityElement(children: .combine)
        .accessibilityValue(level.name)
    }
}

// MARK: - LegendChip

struct LegendChip: View {
    var text = "Today vs. prior 30 days"
    var showsTriangles = true
    var body: some View {
        HStack(spacing: 6) {
            if showsTriangles { DeltaMark(trend: .up); DeltaMark(trend: .down) }
            Text(text).vessText(.caption).foregroundStyle(VessColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(VessColor.bgSunken, in: RoundedRectangle(cornerRadius: VessRadius.sm))
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    var title: String
    var action: String? = nil
    var onAction: () -> Void = {}

    var body: some View {
        HStack {
            Text(title).vessText(.labelCaps).foregroundStyle(VessColor.textSecondary)
            Spacer()
            if let action {
                Button(action: onAction) {
                    HStack(spacing: 2) {
                        Text(action).vessText(.bodyS)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(VessColor.textTertiary)
                    }
                    .foregroundStyle(VessColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - MealRow

struct MealRow: View {
    var time: String          // "07:45"
    var title: String         // "Breakfast" / "Dinner · planned"
    var detail: String
    var kcal: String
    var planned = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(time).vessText(.caption).foregroundStyle(VessColor.textTertiary).frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).vessText(.bodyMStrong).foregroundStyle(VessColor.textPrimary)
                Text(detail).vessText(.bodyS).foregroundStyle(VessColor.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(kcal).vessText(.numberS).foregroundStyle(VessColor.textPrimary)
                Text("kcal").vessText(.caption).foregroundStyle(VessColor.textTertiary)
            }
        }
        .padding(.vertical, 14)
        .opacity(planned ? 0.5 : 1)
        .hairlineBottom()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ListRow  (settings / ingredients / goals)

struct ListRow<Trailing: View>: View {
    var systemImage: String? = nil
    var title: String
    var subtitle: String? = nil
    var value: String? = nil
    var showsChevron = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 17)).foregroundStyle(VessColor.textSecondary).frame(width: VessSize.rowIcon)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).vessText(.bodyM).foregroundStyle(VessColor.textPrimary)
                if let subtitle { Text(subtitle).vessText(.bodyS).foregroundStyle(VessColor.textSecondary) }
            }
            Spacer(minLength: 8)
            if let value { Text(value).vessText(.bodyM).foregroundStyle(VessColor.textSecondary) }
            trailing()
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(VessColor.textTertiary)
            }
        }
        .padding(.vertical, 14)
        .frame(minHeight: VessSize.minTarget)
        .contentShape(Rectangle())
        .hairlineBottom()
    }
}

extension ListRow where Trailing == EmptyView {
    init(systemImage: String? = nil, title: String, subtitle: String? = nil, value: String? = nil, showsChevron: Bool = true) {
        self.init(systemImage: systemImage, title: title, subtitle: subtitle, value: value, showsChevron: showsChevron) { EmptyView() }
    }
}
