import SwiftUI

/// Today (01-today): the day at a glance. Strip, Fuel ring, one editorial
/// line, the breakdown, an insight, intake, meals and hydration. Variants:
/// first log (S1), syncing with Apple Health (S2), full day (I09).
struct TodayView: View {
    @Binding var selectedTab: AppTab

    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health
    @Environment(\.vessOpenAdd) private var openAdd
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var addFood: AddFoodRequest?
    @State private var showCoach = false
    @State private var showFuelInfo = false
    @State private var showEnergy = false
    @State private var showCycle = false
    @State private var showHabits = false
    @State private var undoLog: HydrationLog?
    @State private var undoDismissal: Task<Void, Never>?
    @State private var waterAddCount = 0
    @State private var showError = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            if let profile = store.profile {
                content(profile: profile, now: AppClock.now)
                    // Activity's pushes (workouts, history, statistics) are
                    // registered at the stack root so every link can find them.
                    .activityDestinations()
            }
        }
    }

    private func content(profile: UserProfile, now: Date) -> some View {
        let entries = store.foodEntries(on: now, calendar: calendar)
        let drinks = store.hydrationLogs(on: now, calendar: calendar)
        let history = store.foodEntries(
            from: calendar.date(byAdding: .day, value: -MealRegularity.historyDays, to: calendar.startOfDay(for: now)) ?? now,
            to: calendar.startOfDay(for: now)
        )
        let summary = DaySummary(
            entries: entries,
            hydrationLogs: drinks,
            targets: profile.nutritionTargets,
            waterTargetMilliliters: profile.waterTargetMilliliters,
            day: now,
            now: now,
            calendar: calendar
        )
        let fuel = FuelScore(
            summary: summary,
            hasLoggedFood: !entries.isEmpty,
            regularity: MealRegularity.dayProgress(today: entries, history: history, calendar: calendar)
        )
        let mainMealsLogged = MealType.mainMeals.allSatisfy { !entries.entries(for: $0).isEmpty }
        let trends = trends(now: now)
        let insight = TodayInsight.content(summary: summary, entries: entries, history: history, now: now, calendar: calendar)

        return ScrollView {
            Group {
                if health.state == .syncing {
                    TodaySkeleton()
                } else {
                    VStack(alignment: .leading, spacing: 36) {
                        VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                            TodayHeader(
                                date: now,
                                greeting: Greeting.text(for: now, name: profile.name, calendar: calendar),
                                onCoach: VESSFeatureFlags.coach ? { showCoach = true } : nil
                            )
                            if !entries.isEmpty {
                                TodayMetricStrip(summary: summary, fuel: fuel, health: health.state.snapshot)
                            }
                        }

                        VStack(spacing: VESSSpacing.xl) {
                            TodayFuelRing(fuel: fuel, mainMealsLogged: mainMealsLogged, onInfo: { showFuelInfo = true })
                            Text(summary.editorialLine)
                                .vessTextStyle(.editorialL)
                                .foregroundStyle(VESSColor.text)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                                .accessibilityIdentifier("today.dayWord")
                        }

                        TodayBreakdown(summary: summary, hasLogged: !entries.isEmpty, trends: trends)

                        if let insight {
                            VESSInsightCard(
                                text: Text(insight.text),
                                linkTitle: insight.logMeal.map { "Log \(String(localized: $0.title).lowercased())" } ?? "Break down my day",
                                action: {
                                    if let meal = insight.logMeal {
                                        addFood = AddFoodRequest(meal: meal, day: now)
                                    } else {
                                        showEnergy = true
                                    }
                                }
                            )
                        }

                        if entries.isEmpty {
                            Button {
                                addFood = AddFoodRequest(meal: .likely(at: now, calendar: calendar), day: now)
                            } label: {
                                Label("Log a meal", systemImage: "plus")
                            }
                            .buttonStyle(.vessPrimary)
                            .accessibilityIdentifier("today.addMeal")
                        } else {
                            TodayIntake(summary: summary, entries: entries, calendar: calendar)
                            TodayMeals(entries: entries, onOpenDiary: { selectedTab = .nutrition })
                        }

                        TodayHydration(
                            hydration: summary.hydration,
                            lastDrink: drinks.map(\.loggedAt).max(),
                            onAddWater: { addWater(250, profile: profile) },
                            onAddDrink: { openAdd(.drink) }
                        )

                        if !store.habits.isEmpty {
                            TodayHabitsRow(now: now) { showHabits = true }
                        }

                        // Opt-in: nothing about cycles shows while it's off.
                        if profile.isCycleTrackingOn {
                            TodayCycleRow(now: now, onLog: { openAdd(.cycle) }) { showCycle = true }
                        }
                    }
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground(.fuel)
        .vessTabBarFade()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showEnergy) {
            EnergyDetailView()
        }
        .navigationDestination(isPresented: $showCycle) {
            CycleView()
        }
        .navigationDestination(isPresented: $showHabits) {
            HabitsView()
        }
        .sheet(isPresented: $showFuelInfo) {
            FuelInfoSheet(fuel: fuel)
        }
        .navigationDestination(isPresented: $showCoach) {
            ContentUnavailableView(
                "Coach",
                systemImage: "bubble.left",
                description: Text("Debug builds only. The Coach screen (12) is a static design until its backend is approved.")
            )
            .vessDetailTitle("Coach")
        }
        .safeAreaInset(edge: .bottom) {
            if health.state == .syncing {
                TodaySyncingLabel()
            } else if let undoLog {
                VESSUndoToast(message: Text("Added \(VESSFormat.milliliters(undoLog.volumeMilliliters)) ml of water")) {
                    undo(undoLog)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? VESSMotion.reducedCrossfade : VESSMotion.toast, value: undoLog?.id)
        .vessHaptic(.success, trigger: waterAddCount)
        .sheet(item: $addFood) { request in
            AddSheet(request: request)
        }
        .vessErrorAlert(isPresented: $showError)
    }

    /// Trends for the breakdown rows, from the last 30 days and today so far.
    private func trends(now: Date) -> TodayBreakdown.Trends {
        let start = calendar.date(byAdding: .day, value: -TrendRule.windowDays, to: calendar.startOfDay(for: now)) ?? now
        let food = store.foodEntries(from: start, to: now)
        let drinks = store.hydrationLogs(from: start, to: now)
        func trend(_ samples: [TrendRule.Sample]) -> Trend? {
            TrendRule.trend(samples: samples, now: now, calendar: calendar)
        }
        return TodayBreakdown.Trends(
            energy: trend(food.map { .init(date: $0.loggedAt, value: $0.nutrition.calories) }),
            protein: trend(food.map { .init(date: $0.loggedAt, value: $0.nutrition.proteinGrams) }),
            fibre: trend(food.compactMap { entry in entry.nutrition.fiberGrams.map { .init(date: entry.loggedAt, value: $0) } }),
            hydration: trend(drinks.map { .init(date: $0.loggedAt, value: $0.hydrationMilliliters) })
        )
    }

    // MARK: Actions

    private func addWater(_ milliliters: Double, profile: UserProfile) {
        let preset = DrinkPreset.water
        let drink = preset.drink(
            name: String(localized: preset.title),
            hydrationContributionPercent: profile.hydrationContributionPercent(for: preset)
        )
        let log = drink.log(userID: profile.id, volumeMilliliters: milliliters, at: AppClock.now)
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
            try? await Task.sleep(for: .seconds(5))
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

#Preview("Today · Dark") {
    @Previewable @State var tab = AppTab.today
    TodayView(selectedTab: $tab)
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}

#Preview("Today · Light") {
    @Previewable @State var tab = AppTab.today
    TodayView(selectedTab: $tab)
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.light)
}

#Preview("First log (S1)") {
    @Previewable @State var tab = AppTab.today
    TodayView(selectedTab: $tab)
        .previewEnvironment(LocalStore.preview(.profileOnly), health: .notConnected)
        .preferredColorScheme(.dark)
}

#Preview("Syncing (S2)") {
    @Previewable @State var tab = AppTab.today
    TodayView(selectedTab: $tab)
        .previewEnvironment(LocalStore.preview(), health: .syncing)
        .preferredColorScheme(.dark)
}
