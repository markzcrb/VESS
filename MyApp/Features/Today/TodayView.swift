import SwiftUI

/// Today: the daily command center. A single editorial column that answers
/// "how is my day going, and what's next?" without becoming a dashboard.
struct TodayView: View {
    @Binding var selectedTab: AppTab

    @Environment(LocalStore.self) private var store
    @State private var addFood: AddFoodRequest?
    @State private var undoLog: HydrationLog?
    @State private var undoDismissal: Task<Void, Never>?
    @State private var waterAddCount = 0
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            if let profile = store.profile {
                content(profile: profile, now: .now)
            }
        }
    }

    private func content(profile: UserProfile, now: Date) -> some View {
        let entries = store.foodEntries(on: now, calendar: calendar)
        let history = store.foodEntries(
            from: calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now)) ?? now,
            to: calendar.startOfDay(for: now)
        )
        let summary = DaySummary(
            entries: entries,
            hydrationLogs: store.hydrationLogs(on: now, calendar: calendar),
            targets: profile.nutritionTargets,
            waterTargetMilliliters: profile.waterTargetMilliliters,
            day: now,
            now: now,
            calendar: calendar
        )
        let todaysWorkout = store.workouts.first { workout in
            [workout.scheduledDate, workout.completedAt].contains { date in
                date.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            }
        }
        let expiring = store.inventory
            .filter { $0.status == .available && $0.expirationStatus(now: now, calendar: calendar).needsAttention }
            .sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }

        return ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                // The Day Word and the day's calories read as one composition.
                VStack(alignment: .leading, spacing: VESSSpacing.xxl) {
                    TodayHeader(
                        date: now,
                        greeting: Greeting.text(for: now, name: profile.name, calendar: calendar),
                        summary: summary
                    )
                    CaloriesOverview(summary: summary)
                }

                TodayMealsSection(
                    entries: entries,
                    history: history,
                    now: now,
                    calendar: calendar,
                    onAdd: { meal in addFood = AddFoodRequest(meal: meal, day: now) },
                    onOpenDiary: { selectedTab = .nutrition }
                )

                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    WaterOverview(hydration: summary.hydration) {
                        addWater(250, profile: profile)
                    }
                    if let todaysWorkout {
                        Rectangle()
                            .fill(VESSColor.divider)
                            .frame(height: 0.5)
                        ActivityOverview(workout: todaysWorkout)
                    }
                }

                if !expiring.isEmpty {
                    ExpiringSoonSection(items: expiring, now: now, calendar: calendar)
                }

                if let insight = store.insights.first {
                    VESSMarginNote(text: Text(insight.body))
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .background(VESSColor.background)
        // An untitled inline bar hosts the native "+". Without a title the
        // automatic edge effect is too faint, so use the defined (hard) edge:
        // rows never collide with the "+" or the clock while scrolling.
        .scrollEdgeEffectStyle(.hard, for: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add food", systemImage: "plus") {
                    addFood = AddFoodRequest(meal: .likely(at: now, calendar: calendar), day: now)
                }
                .accessibilityIdentifier("today.addFood")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let undoLog {
                VESSUndoToast(message: Text("Added \(VESSFormat.milliliters(undoLog.volumeMilliliters)) ml of water")) {
                    undo(undoLog)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: undoLog?.id)
        .sensoryFeedback(.success, trigger: waterAddCount)
        .sheet(item: $addFood) { request in
            AddFoodSheet(request: request)
        }
        .vessErrorAlert(isPresented: $showError)
    }

    // MARK: Actions

    private func addWater(_ milliliters: Double, profile: UserProfile) {
        let preset = DrinkPreset.water
        let drink = preset.drink(
            name: String(localized: preset.title),
            hydrationContributionPercent: profile.hydrationContributionPercent(for: preset)
        )
        let log = drink.log(userID: profile.id, volumeMilliliters: milliliters, at: .now)
        do {
            try store.add(log)
            waterAddCount += 1
            showUndo(for: log)
        } catch {
            showError = true
        }
    }

    private func showUndo(for log: HydrationLog) {
        undoDismissal?.cancel()
        undoLog = log
        undoDismissal = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            undoLog = nil
        }
    }

    private func undo(_ log: HydrationLog) {
        undoDismissal?.cancel()
        undoLog = nil
        do {
            try store.deleteHydrationLog(id: log.id)
        } catch {
            showError = true
        }
    }
}

#Preview("Sample day") {
    @Previewable @State var tab = AppTab.today
    TodayView(selectedTab: $tab)
        .environment(LocalStore.preview())
}

#Preview("First day") {
    @Previewable @State var tab = AppTab.today
    TodayView(selectedTab: $tab)
        .environment(LocalStore.preview(.profileOnly))
}

#Preview("Sample day, dark") {
    @Previewable @State var tab = AppTab.today
    TodayView(selectedTab: $tab)
        .environment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
