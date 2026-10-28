import SwiftUI

/// Opens the Add sheet on a type: Today's Add drink and cycle Log,
/// Habits +, Activity's Add workout. Set by `RootTabView`; call it like a
/// function, `openAdd(.drink)`.
struct VESSOpenAddAction {
    let handler: (AddType) -> Void

    func callAsFunction(_ type: AddType) { handler(type) }

    /// Does nothing: the default outside the tab view, and in previews.
    static let none = VESSOpenAddAction { _ in }
}

extension EnvironmentValues {
    @Entry var vessOpenAdd: VESSOpenAddAction = .none
}

/// 21, 22: one "+" for everything. "ADD" with the X on the left, the type
/// carousel, and the chosen type's content below it, swapped in place.
/// Each type reuses its existing screen. Opens on Food, on the type an
/// entry point asks for, or on the type used last within the past hour.
struct AddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let day: Date
    private let collection: FoodCollection
    @State private var meal: MealType
    @State private var selection: AddType
    @State private var path: [FoodRoute] = []
    /// +1 when the new type is to the right of the old one, -1 to the left.
    @State private var direction: CGFloat = 1
    /// The last menu read in Photo › Menu; gone when the sheet closes.
    @State private var menu: MenuScanResult?

    private static let lastTypeKey = "add.lastType"
    private static let lastTypeAtKey = "add.lastTypeAt"

    init(request: AddFoodRequest) {
        self.day = request.day
        self.collection = request.collection
        _meal = State(initialValue: request.meal)
        let defaults = UserDefaults.standard
        let lastAt = defaults.double(forKey: Self.lastTypeAtKey)
        // Cycle is checked against the profile in `types`; a type that's
        // hidden falls back to Food there.
        _selection = State(initialValue: AddTypeRules.initial(
            requested: request.type,
            lastUsed: defaults.string(forKey: Self.lastTypeKey).flatMap(AddType.init(rawValue:)),
            lastUsedAt: lastAt > 0 ? Date(timeIntervalSince1970: lastAt) : nil,
            now: AppClock.now,
            visible: AddTypeRules.visible(photo: true, cycle: true)
        ))
    }

    private var types: [AddType] {
        AddTypeRules.visible(photo: true, cycle: store.profile?.isCycleTrackingOn == true)
    }

    /// The selection, or Food when it isn't shown (cycle tracking off).
    private var current: AddType {
        types.contains(selection) ? selection : .food
    }

    var body: some View {
        NavigationStack(path: $path) {
            // Paged: the old type moves out by the full width towards the
            // swipe, the new one comes in from the other side, both opaque,
            // side by side, never on top of each other (MOTION.md, Add sheet).
            ZStack {
                content(current)
                    .id(current)
                    .transition(swapTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Clips the paging sideways only: content still scrolls under
            // the home indicator instead of stopping above it.
            .mask(Rectangle().ignoresSafeArea(edges: .bottom))
            // One canvas for every type: their own backgrounds stand down.
            .background(VESSColor.background)
            .environment(\.vessInAddSheet, true)
            .safeAreaInset(edge: .top, spacing: 0) { carousel }
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(Text("Add"))
                .toolbar {
                    closeButton
                    ToolbarItem(placement: .principal) {
                        Text("Add")
                            .vessTextStyle(.labelCaps)
                            .foregroundStyle(VESSColor.text)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .navigationDestination(for: FoodRoute.self) { route in
                    destination(for: route)
                        .toolbar { closeButton }
                }
                .onAppear { AddSheetTiming.appeared() }
        }
        .presentationCornerRadius(VESSRadius.sheet)
        .presentationDragIndicator(.visible)
        // The type you were on when closing is the one used last.
        .onDisappear {
            UserDefaults.standard.set(current.rawValue, forKey: Self.lastTypeKey)
            UserDefaults.standard.set(AppClock.now.timeIntervalSince1970, forKey: Self.lastTypeAtKey)
        }
    }

    private var carousel: some View {
        VStack(spacing: 0) {
            AddTypeCarousel(types: types, selection: Binding(get: { current }, set: select))
                .padding(.top, VESSSpacing.xs)
                .padding(.bottom, VESSSpacing.md)
            VESSHairline()
                .padding(.horizontal, VESSSpacing.screenInset)
        }
        .background(VESSColor.background)
    }

    /// Sets the direction first, so the outgoing view leaves the right way.
    private func select(_ type: AddType) {
        guard type != current else { return }
        direction = (types.firstIndex(of: type) ?? 0) > (types.firstIndex(of: current) ?? 0) ? 1 : -1
        withAnimation(reduceMotion ? VESSMotion.addSwapReduced : VESSMotion.addSwap) {
            selection = type
        }
    }

    private var swapTransition: AnyTransition {
        // Reduce Motion: old out, then new in; never both at once.
        guard !reduceMotion else {
            return .asymmetric(
                insertion: AnyTransition.opacity.animation(VESSMotion.addFadeIn.delay(VESSMotion.addFadeOutDuration)),
                removal: AnyTransition.opacity.animation(VESSMotion.addFadeOut)
            )
        }
        let forward = direction > 0
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal: .move(edge: forward ? .leading : .trailing)
        )
    }

    @ViewBuilder
    private func content(_ type: AddType) -> some View {
        switch type {
        case .food:
            FoodSearchHome(day: day, meal: $meal, path: $path, collection: collection)
        case .quickAdd:
            QuickAddForm(day: day, meal: $meal, embedded: true, onLogged: { dismiss() })
        case .drink:
            AddDrinkSheet(day: day, embedded: true)
        case .supplements:
            AddSupplementsContent(day: day)
        case .workout:
            AddWorkoutView(embedded: true)
        case .habits:
            AddHabitsContent()
        case .weight:
            AddWeightContent()
        case .cycle:
            CycleDayForm(date: day, showsClose: false, onDone: { dismiss() })
        case .photo:
            AddPhotoContent(day: day, meal: $meal, menu: $menu, onSearchInstead: { select(.food) },
                            onTypeNumber: { path.append(.barcode) },
                            onAddManually: { code in path.append(.createFood(barcode: code)) },
                            onLogged: { dismiss() })
        }
    }

    @ViewBuilder
    private func destination(for route: FoodRoute) -> some View {
        switch route {
        case .food(let food):
            FoodDetailView(food: food, day: day, meal: $meal, onLogged: { dismiss() })
        case .createFood(let barcode):
            // Replace the form with the new food, so Back returns to search.
            CustomFoodForm(barcode: barcode, onSaved: { food in path = [.food(food)] })
        case .barcode:
            BarcodeLookupView(onFound: { food in path.append(.food(food)) })
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) { dismiss() }
        }
    }
}

/// Habits in the Add sheet: today's list with ticks, and Add a habit (16).
struct AddHabitsContent: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthDataStore.self) private var health

    @State private var adding = false

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let habits = store.habits
        let log = HabitLogLoader.log(
            store: store,
            health: health.state.snapshot,
            from: calendar.date(byAdding: .day, value: -7, to: now) ?? now,
            through: now,
            calendar: calendar
        )
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.section) {
                if habits.isEmpty {
                    Text("Add a habit or two. Some track themselves from what you already log.")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HabitTodayList(habits: habits, now: now, log: log)
                }
                Button("Add a habit") { adding = true }
                    .buttonStyle(habits.isEmpty ? .vessPrimary : .vessSecondary)
                    .accessibilityIdentifier("add.habits.add")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
            .padding(.bottom, VESSSpacing.huge)
        }
        .sheet(isPresented: $adding) {
            AddHabitSheet(editing: nil)
        }
    }
}

/// Weight in the Add sheet: the profile weight, in steps of 0.1 kg. Weight
/// from Apple Health is only read; VESS never writes to Health.
struct AddWeightContent: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.vessHaptics) private var haptics
    @Environment(\.dismiss) private var dismiss

    @State private var value: Double?
    @State private var showError = false

    private static let range = 30.0...300.0
    private static let step = 0.1

    var body: some View {
        let weight = value ?? store.profile?.weightKilograms ?? 70
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VESSSectionHeader(title: "Weight")
                HStack {
                    VESSIconButton(systemImage: "minus", label: "Less") { value = max(Self.range.lowerBound, weight - Self.step) }
                        .disabled(weight <= Self.range.lowerBound)
                    Spacer()
                    Text(verbatim: "\(weight.formatted(.number.precision(.fractionLength(1))))\u{00A0}kg")
                        .vessTextStyle(.displayM)
                        .monospacedDigit()
                        .foregroundStyle(VESSColor.text)
                        .contentTransition(.numericText())
                    Spacer()
                    VESSIconButton(systemImage: "plus", label: "More") { value = min(Self.range.upperBound, weight + Self.step) }
                        .disabled(weight >= Self.range.upperBound)
                }
                .accessibilityElement(children: .contain)
                .accessibilityValue(Text(verbatim: "\(weight.formatted(.number.precision(.fractionLength(1))))\u{00A0}kg"))
                Text("Updates the weight in your profile. Weight from Apple Health is read, never written.")
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
        }
        .vessBottomAction(background: VESSColor.background) {
            Button("Save") { save(weight) }
                .buttonStyle(.vessPrimary)
                .accessibilityIdentifier("add.weight.save")
        }
        .vessErrorAlert(isPresented: $showError)
    }

    private func save(_ weight: Double) {
        guard var profile = store.profile else { return }
        profile.weightKilograms = (weight * 10).rounded() / 10
        do {
            try store.saveProfile(profile)
            haptics.play(.success)
            dismiss()
        } catch {
            showError = true
        }
    }
}

#if DEBUG
#Preview("Add · Food") {
    AddSheet(request: AddFoodRequest(meal: .dinner, day: AppClock.now, type: .food))
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}

#Preview("Add · Supplements") {
    AddSheet(request: AddFoodRequest(meal: .dinner, day: AppClock.now, type: .supplements))
        .previewEnvironment(LocalStore.preview())
        .preferredColorScheme(.dark)
}
#endif
