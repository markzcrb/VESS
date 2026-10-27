import SwiftUI

/// "Edit rings": the chosen rings first (drag to reorder, swipe to remove),
/// then the rest to add, by Nutrition / Activity / Body / Mind. 1–12 rings;
/// each change is saved to the profile at once.
struct EditRingsSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showError = false

    var body: some View {
        let profile = store.profile
        let now = AppClock.now
        let rings = profile?.todayRingList(on: now, calendar: .current) ?? TodayRingRules.defaultRings
        let available = TodayRingRules.available(
            cycleTrackingOn: profile?.isCycleTrackingOn ?? false,
            showsBMI: profile.map { BodyRules.showsBMI(profile: $0, now: now, calendar: .current) } ?? false
        )

        NavigationStack {
            List {
                Section {
                    // Drag handles only (no system delete control); each row has
                    // a quiet Remove.
                    ForEach(rings, id: \.self) { ring in
                        HStack(spacing: VESSSpacing.sm) {
                            row(ring)
                            if TodayRingRules.canRemove(rings) {
                                Button { save(TodayRingRules.removing(ring, from: rings)) } label: {
                                    Text("Remove")
                                        .vessTextStyle(.bodyS)
                                        .foregroundStyle(VESSColor.secondaryText)
                                        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text("Remove \(Text(ring.title))"))
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in
                        var moved = rings
                        moved.move(fromOffsets: from, toOffset: to)
                        save(moved)
                    }
                } header: {
                    header(Text("Your rings"))
                } footer: {
                    Text("Drag to reorder. At least 1 ring, up to \(TodayRingRules.maximum).")
                        .vessTextStyle(.caption)
                        .foregroundStyle(VESSColor.tertiaryText)
                }

                ForEach(TodayRing.Group.allCases, id: \.self) { group in
                    let rest = available.filter { $0.group == group && !rings.contains($0) }
                    if !rest.isEmpty {
                        Section {
                            ForEach(rest, id: \.self) { ring in
                                Button { save(TodayRingRules.adding(ring, to: rings)) } label: {
                                    HStack(spacing: VESSSpacing.sm) {
                                        row(ring)
                                        Image(systemName: "plus.circle")
                                            .foregroundStyle(VESSColor.accent)
                                            .accessibilityHidden(true)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!TodayRingRules.canAdd(rings))
                                .accessibilityHint("Adds this ring")
                            }
                        } header: {
                            header(Text("Add · \(Text(group.title))"))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(VESSColor.card)
            .environment(\.editMode, .constant(.active))
            .vessDetailTitle("Edit rings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .vessErrorAlert(isPresented: $showError)
        }
        .presentationDetents([.large])
        .presentationCornerRadius(VESSRadius.sheet)
    }

    private func row(_ ring: TodayRing) -> some View {
        // At accessibility sizes the icon sits above the text, so it never
        // covers a wrapped line.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xxs))
            : AnyLayout(HStackLayout(spacing: VESSSpacing.sm))
        return layout {
            Image(systemName: ring.symbol)
                .foregroundStyle(ring.metric.tint)
                .frame(width: VESSSize.rowIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ring.title)
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.text)
                if let subtitle = ring.subtitle {
                    Text(subtitle)
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: VESSHitTarget.minimum)
        .listRowBackground(Color.clear)
    }

    private func header(_ text: Text) -> some View {
        text
            .vessTextStyle(.labelCaps)
            .foregroundStyle(VESSColor.secondaryText)
    }

    private func save(_ rings: [TodayRing]) {
        guard var profile = store.profile else { return }
        profile.todayRings = rings.map(\.rawValue)
        do { try store.saveProfile(profile) } catch { showError = true }
    }
}
