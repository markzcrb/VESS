import SwiftUI

/// "Edit rings": the chosen rings first (drag to reorder, swipe to remove),
/// then the rest to add, by Nutrition / Activity / Body / Mind. 1–12 rings;
/// each change is saved to the profile at once.
struct EditRingsSheet: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showError = false

    var body: some View {
        let profile = store.profile
        let rings = profile?.todayRingList ?? TodayRingRules.defaultRings
        let available = TodayRingRules.available(cycleTrackingOn: profile?.isCycleTrackingOn ?? false)

        NavigationStack {
            List {
                Section {
                    ForEach(rings, id: \.self) { ring in
                        row(ring)
                            .deleteDisabled(!TodayRingRules.canRemove(rings))
                    }
                    .onMove { from, to in
                        var moved = rings
                        moved.move(fromOffsets: from, toOffset: to)
                        save(moved)
                    }
                    .onDelete { offsets in
                        var kept = rings
                        for index in offsets.sorted(by: >) where TodayRingRules.canRemove(kept) { kept.remove(at: index) }
                        save(kept)
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
        HStack(spacing: VESSSpacing.sm) {
            Image(systemName: ring.symbol)
                .foregroundStyle(ring.metric.tint)
                .frame(width: VESSSize.rowIcon)
                .accessibilityHidden(true)
            Text(ring.title)
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
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
