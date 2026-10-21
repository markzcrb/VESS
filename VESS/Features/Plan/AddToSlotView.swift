import SwiftUI

/// A02: choose a meal for one slot. Suggested (the plan rule), Saved
/// (favourites and your own foods) or Recent (meals you've logged).
/// Replaces `replacing` when given.
struct AddToSlotView: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let day: Date
    let meal: MealType
    var replacing: PlannedMeal?

    private enum Tab: Hashable { case suggested, saved, recent }

    @State private var tab: Tab = .suggested
    @State private var query = ""
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let options = candidates(now: now)

        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                    VESSSectionHeader(title: "Search")
                    HStack(spacing: VESSSpacing.sm) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(VESSColor.secondaryText)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .accessibilityHidden(true)
                        // Drawn placeholder, as in FoodSearchSheet: a custom
                        // prompt loses the scaled font at large sizes.
                        TextField("Search meals and foods", text: $query, prompt: Text(verbatim: ""))
                            .vessTextStyle(.bodyM)
                            .background(alignment: .leading) {
                                if query.isEmpty {
                                    Text("Search meals and foods")
                                        .vessTextStyle(.bodyM)
                                        .foregroundStyle(VESSColor.tertiaryText)
                                        .lineLimit(1)
                                        .accessibilityHidden(true)
                                }
                            }
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("addToSlot.search")
                    }
                    .padding(.horizontal, VESSSpacing.md)
                    .frame(minHeight: VESSHitTarget.control)
                    .background(VESSColor.fill, in: RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous).strokeBorder(VESSColor.divider))
                }

                VESSSegmented(selection: $tab, options: [(.suggested, "Suggested"), (.saved, "Saved"), (.recent, "Recent")])

                if tab == .suggested {
                    Text("Good fits for this slot")
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                }

                if options.isEmpty {
                    Text(emptyText)
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VESSRowGroup {
                        ForEach(options, id: \.self) { candidate in
                            Button { add(candidate) } label: {
                                VESSRow(
                                    title: Text(candidate.name),
                                    subtitle: MealSuggestions.reason(candidate, day: day, pantry: store.inventory, now: now, calendar: calendar).text,
                                    subtitleLineLimit: 2
                                ) {
                                    Text("\(VESSFormat.calories(candidate.nutrition.calories)) kcal")
                                        .vessTextStyle(.bodyM)
                                        .foregroundStyle(VESSColor.secondaryText)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Adds it to \(Text(meal.title))"))
                            .accessibilityIdentifier("addToSlot.\(candidate.name)")
                        }
                    }
                    .vessHairlineBottom()
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .scrollDismissesKeyboard(.immediately)
        .vessScreenBackground()
        .vessDetailTitle(title)
        .toolbar(.hidden, for: .tabBar)
        .vessErrorAlert(isPresented: $showError)
    }

    /// "Add to Thu dinner".
    private var title: LocalizedStringResource {
        let weekday = day.formatted(.dateTime.weekday(.abbreviated))
        return "Add to \(weekday) \(String(localized: meal.title).lowercased())"
    }

    private var emptyText: LocalizedStringResource {
        switch tab {
        case .suggested: "Nothing fits this slot yet. Meals you log and foods you save show up here."
        case .saved: "Favourites and foods you create appear here."
        case .recent: "Meals you log appear here."
        }
    }

    private func candidates(now: Date) -> [MealSuggestions.Candidate] {
        guard let profile = store.profile else { return [] }
        let list: [MealSuggestions.Candidate] = switch tab {
        case .suggested:
            MealSuggestions.ranked(
                for: meal, on: day, candidates: PlanCandidates.all(store: store, now: now, calendar: calendar),
                pantry: store.inventory, profile: profile, now: now, calendar: calendar
            )
        case .saved: PlanCandidates.saved(store: store)
        case .recent:
            PlanCandidates.all(store: store, now: now, calendar: calendar).filter {
                if case .foods = $0.source { true } else { false }
            }
        }
        let trimmed = FoodSearch.normalized(query)
        guard !trimmed.isEmpty else { return list }
        return list.filter { FoodSearch.normalized($0.name).contains(trimmed) }
    }

    private func add(_ candidate: MealSuggestions.Candidate) {
        do {
            if let replacing { try store.deletePlannedMeal(id: replacing.id) }
            try store.save(PlannedMeal(candidate: candidate, day: day, meal: meal, now: AppClock.now, calendar: calendar))
            dismiss()
        } catch {
            showError = true
        }
    }
}
