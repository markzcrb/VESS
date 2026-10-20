//  RedesignGallery.swift
//  One scrollable page with every VESS component. Compare against Design/components/*.png
//  and Design/screens/01-today.png before building screens.

import SwiftUI

struct RedesignGallery: View {
    @State private var range = 0
    @State private var tab: VessTab = .today

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VessSpace.section) {
                Text("A steady day. Protein is the one to watch.").vessText(.editorialL).foregroundStyle(VessColor.textPrimary)

                HStack {
                    MetricStripItem(value: "78", label: "Fuel", progress: 0.78, metric: .fuel)
                    Spacer(); MetricStripItem(value: "77", label: "Energy", progress: 0.77, metric: .energy)
                    Spacer(); MetricStripItem(value: "77", label: "Protein", progress: 0.77, metric: .protein)
                    Spacer(); MetricStripItem(value: "73", label: "Water", progress: 0.73, metric: .water)
                    Spacer(); MetricStripItem(value: "80", label: "Steps", progress: 0.80, metric: .activity)
                }

                ScoreRing(value: "78", label: "Fuel", sublabel: "3 of 4 meals logged", progress: 0.78)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 0) {
                    MetricRow(systemImage: "flame", label: "Energy", value: "1,840", trend: .up)
                    MetricRow(systemImage: "fish", label: "Protein", value: "108 g", trend: .down)
                    MetricRow(systemImage: "leaf", label: "Fibre", value: "21 g", trend: .flat)
                    MetricRow(systemImage: "drop", label: "Hydration", value: "1.6 L", trend: .up)
                    LegendChip().padding(.top, 14)
                }

                VStack(spacing: 0) {
                    StatusRow(systemImage: "flame", label: "Energy vs. target", value: "77%", level: .sufficient)
                    StatusRow(systemImage: "clock", label: "Meal regularity", value: "92%", level: .optimal)
                    StatusRow(systemImage: "sun.max", label: "Before noon", value: "34%", level: .poor)
                }

                InsightCard(text: "Protein is at 108 of 140 g, and 70% of it came after noon. A protein-led dinner closes the gap.")

                VStack(spacing: 22) {
                    MacroBar(name: "Protein", value: "+31 g", target: "→ 139 / 140 g", logged: 108/140, adding: 31/140, metric: .protein)
                    MacroBar(name: "Water", value: "1.6", target: "/ 2.2 L", adding: 0.73, metric: .water)
                }

                VStack(spacing: 8) {
                    ImpactRow(label: "Drank 2 L or more", impactPercent: 24)
                    ImpactRow(label: "Ate fish", impactPercent: 2, isNew: true)
                    ImpactRow(label: "Alcohol", impactPercent: -11)
                }

                VStack(spacing: 0) {
                    SectionHeader(title: "Meals", action: "Diary")
                    MealRow(time: "07:45", title: "Breakfast", detail: "Greek yogurt, oats, blueberries", kcal: "520")
                    MealRow(time: "19:30", title: "Dinner · planned", detail: "Miso-glazed cod, bok choy, rice", kcal: "620", planned: true)
                    ListRow(systemImage: "calendar", title: "Plan ready · 2,350 kcal", subtitle: "Overnight oats · Tuna niçoise · Prawn curry")
                }

                VessSegmented(selection: $range, options: [(0, "Day"), (1, "Week"), (2, "Month")])

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(label: "Recent", selected: true); Chip(label: "Saved meals"); Chip(label: "Favourites")
                    }
                }

                HStack(spacing: 8) {
                    VessTag(label: "Recorded", tone: .positive); VessTag(label: "Entered")
                    VessTag(label: "Missing", tone: .warning); VessTag(label: "Use by Thu", tone: .accent)
                }

                HStack { IconButton(systemImage: "plus"); IconButton(systemImage: "checkmark", filled: true) }
                Button("Add to dinner · 312 kcal") {}.buttonStyle(.vessPrimary)
                Button("Log a workout") {}.buttonStyle(.vessSecondary)
            }
            .padding(.horizontal, VessSpace.screenMargin)
            .padding(.bottom, 140)
        }
        .vessScreenBackground(.fuel)
        .safeAreaInset(edge: .bottom) { VessTabBar(selection: $tab, onAdd: {}) }
    }
}

#Preview("Dark") { RedesignGallery().preferredColorScheme(.dark) }
#Preview("Light") { RedesignGallery().preferredColorScheme(.light) }
#Preview("AX5") { RedesignGallery().preferredColorScheme(.dark).dynamicTypeSize(.accessibility5) }
