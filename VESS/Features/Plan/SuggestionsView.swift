import SwiftUI

/// A07: one suggestion per open slot (the local plan rule), each
/// deselectable, then "Add N meals to plan". There is no loading or error
/// state: the rule runs on the device and is instant.
struct SuggestionsView: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let openSlots: [(day: Date, meal: MealType)]
    /// Names already planned this week, so nothing repeats.
    let plannedNames: Set<String>

    @State private var deselected: Set<Int> = []
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let suggestions = suggestions(now: now)
        let selected = suggestions.indices.filter { !deselected.contains($0) }

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    Text("^[\(openSlots.count) open slot](inflect: true), considered.")
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(suggestions.isEmpty
                         ? "Nothing fits yet. Log a few meals or save some foods, and suggestions will follow."
                         : "These use what's in your pantry first. Check use-by dates before cooking.")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                        Text("\(Text(suggestion.day, format: .dateTime.weekday(.wide))) · \(Text(suggestion.meal.title))")
                            .vessTextStyle(.labelCaps)
                            .foregroundStyle(VESSColor.secondaryText)
                            .accessibilityAddTraits(.isHeader)
                        Button { toggle(index) } label: {
                            VESSRow(
                                title: Text(suggestion.candidate.name),
                                subtitle: suggestion.reason.text,
                                subtitleLineLimit: 2
                            ) {
                                Image(systemName: deselected.contains(index) ? "circle" : "checkmark")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(deselected.contains(index) ? VESSColor.tertiaryText : VESSColor.text)
                                    .frame(width: VESSSize.rowIcon)
                            } trailing: {
                                Text("\(VESSFormat.calories(suggestion.candidate.nutrition.calories)) kcal")
                                    .vessTextStyle(.bodyM)
                                    .foregroundStyle(VESSColor.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(deselected.contains(index) ? [] : .isSelected)
                        .accessibilityIdentifier("suggestion.\(index)")
                        .vessHairlineBottom()
                    }
                }

                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                        if suggestions.count < openSlots.count {
                            Text("^[\(openSlots.count - suggestions.count) slot](inflect: true) had nothing that fits yet. Add them from the plan when you're ready.")
                        }
                        Text("\(selected.count) of \(suggestions.count) selected · You can change any later")
                    }
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground()
        .vessDetailTitle("Suggestions")
        .vessBottomAction(background: VESSColor.background) {
            Button {
                add(selected.map { suggestions[$0] })
            } label: {
                Text("Add ^[\(selected.count) meal](inflect: true) to plan")
            }
            .buttonStyle(.vessPrimary)
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("suggestions.add")
        }
        .vessErrorAlert(isPresented: $showError)
    }

    private func suggestions(now: Date) -> [MealSuggestions.Suggestion] {
        guard let profile = store.profile else { return [] }
        return MealSuggestions.suggest(
            openSlots: openSlots,
            candidates: PlanCandidates.all(store: store, now: now, calendar: calendar),
            pantry: store.inventory,
            profile: profile,
            excludingNames: plannedNames,
            now: now,
            calendar: calendar
        )
    }

    private func toggle(_ index: Int) {
        if deselected.contains(index) { deselected.remove(index) } else { deselected.insert(index) }
    }

    private func add(_ chosen: [MealSuggestions.Suggestion]) {
        do {
            for suggestion in chosen {
                try store.save(PlannedMeal(candidate: suggestion.candidate, day: suggestion.day, meal: suggestion.meal, now: AppClock.now, calendar: calendar))
            }
            dismiss()
        } catch {
            showError = true
        }
    }
}
