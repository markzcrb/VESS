import StoreKit
import SwiftUI

/// P02 UMEVA+: what it adds, two plans side by side (Annual preselected
/// with its 7-day trial and the trial timeline; Monthly without a trial),
/// the required subscription text, and Free vs UMEVA+ in a sheet. Prices
/// come from StoreKit (`displayPrice`); the euro values are DEBUG
/// fallbacks only. Buying needs an account (the purchase is tied to it);
/// signed out, the button signs in first and then continues. The plan and
/// limits come from the server (`PlanStore`). The button and its text are
/// pinned at the bottom, with their height reserved (not at accessibility
/// sizes, where the bar would fill the screen).
struct VESSPlusView: View {
    enum Plan: String, CaseIterable, Identifiable {
        case monthly, annual
        var id: String { rawValue }

        /// "<bundle id>.plus.monthly" / ".plus.annual" (App Store Connect
        /// and VESS.storekit for local testing).
        var productID: String {
            let bundle = Bundle.main.bundleIdentifier ?? "app.umeva.ios"
            switch self {
            case .monthly: return "\(bundle).plus.monthly"
            case .annual: return "\(bundle).plus.annual"
            }
        }

        /// DEBUG fallbacks when StoreKit has no product (Release shows "—").
        var fallbackPrice: Decimal {
            switch self {
            case .monthly: 7.99
            case .annual: 49.99
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ReminderService.self) private var reminders
    @Environment(LocalStore.self) private var store
    @Environment(\.vessOpenCoach) private var openCoach
    @Environment(AccountStore.self) private var account
    @Environment(PlanStore.self) private var planStore
    /// Signed out at Subscribe: sign in, then the purchase continues.
    @State private var showSignIn = false
    @State private var continuesAfterSignIn = false
    /// After a verified purchase, until the server confirms (at most 5 s).
    @State private var isActivating = false
    @State private var plan: Plan = .annual
    /// B04, after a verified purchase (never after Restore).
    @State private var welcome: PlusWelcome?
    @State private var products: [String: Product] = [:]
    /// Whether the annual trial can still be offered (StoreKit says).
    @State private var trialEligible = true
    @State private var isSubscribed = false
    @State private var isWorking = false
    @State private var showManage = false
    @State private var showCompare = false
    @State private var showPrivacy = false
    @State private var message: String?

    /// UMEVA's Terms of Use (which link Apple's standard EULA).
    private static let termsURL = LegalLinks.terms

    private var hasTrial: Bool { plan == .annual && trialEligible }
    /// The button, its text and links are pinned under the page except at
    /// accessibility sizes, where they'd fill the screen and end the page.
    private var pinsButton: Bool { !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    header
                    // The plans first, so both cards are in full view above
                    // the pinned button at the default size.
                    plans
                    features
                    if hasTrial { timeline }
                    if !pinsButton { action }
                }
                .padding(.horizontal, VESSSpacing.md)
                .padding(.top, VESSSpacing.xs)
                .padding(.bottom, VESSSpacing.xl)
            }
            // Content never shows through under Close and Restore.
            .scrollEdgeEffectStyle(.hard, for: .top)
            .background(VESSColor.background)
            // An inset, so the bar's height is reserved: the cards and the
            // rest of the page always end above it, never under it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if pinsButton {
                    action
                        .padding(.horizontal, VESSSpacing.md)
                        .padding(.top, VESSSpacing.sm)
                        .padding(.bottom, VESSSpacing.xs)
                        .background(VESSColor.background.ignoresSafeArea(edges: .bottom))
                        .overlay(alignment: .top) { VESSHairline() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: restore) {
                        Text("Restore")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.secondaryText)
                            .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityIdentifier("plus.restore")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(isPresented: $showPrivacy) { PrivacyView() }
            .sheet(isPresented: $showSignIn, onDismiss: {
                if continuesAfterSignIn, account.isSignedIn {
                    continuesAfterSignIn = false
                    subscribe()
                }
            }) {
                AISignInSheet(title: "Sign in to buy UMEVA+.",
                              text: "UMEVA+ is tied to your UMEVA account, so its limits follow you. Your log stays on this iPhone.")
            }
            .sheet(isPresented: $showCompare) { VESSPlusComparison() }
            .manageSubscriptionsSheet(isPresented: $showManage)
        }
        .fullScreenCover(item: $welcome) { welcome in
            PlusWelcomeView(welcome: welcome, onAskCoach: {
                openCoach()
                dismiss()
            }, onDone: { dismiss() })
        }
        .task {
            await reminders.refreshAuthorization()
            await load()
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text("UMEVA+")
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.accent)
            Text("Coach, Chef and photo estimates, every day.")
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Logging, recipes, pantry, grocery and Apple Health stay free.")
                .vessTextStyle(.bodyS)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            let plus = UMEVAPlusLimits.plus
            VESSFeatureRow(systemImage: "bubble.left", title: Text("AI Coach"),
                           detail: Text("\(plus.coachQuestions) questions a day, with charts from your own data"))
            VESSFeatureRow(systemImage: "camera", title: Text("Photo and menu estimates"),
                           detail: Text("\(plus.photoEstimates) a day: your plate or a restaurant menu"))
            VESSFeatureRow(systemImage: "fork.knife", title: Text("AI Chef"),
                           detail: Text("\(plus.chefRecipes) recipes a day from what's in your pantry"))
            VESSFeatureRow(systemImage: "chart.bar", title: Text("Insights and Health patterns"),
                           detail: Text("All history, plus sleep, stress and heart patterns"))
        }
    }

    /// Side by side; stacked at accessibility sizes.
    private var plans: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: VESSSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: VESSSpacing.sm))
        return layout {
            VESSPlanCard(
                title: "Annual", price: Text(verbatim: price(.annual)),
                detail: Text("a year · \(monthlyEquivalent) a month"),
                badge: Text(verbatim: "\u{2212}\(savingPercent)%"),
                isSelected: plan == .annual
            ) { select(.annual) }
            .accessibilityIdentifier("plus.plan.annual")
            VESSPlanCard(
                title: "Monthly", price: Text(verbatim: price(.monthly)),
                detail: Text("a month"),
                isSelected: plan == .monthly
            ) { select(.monthly) }
            .accessibilityIdentifier("plus.plan.monthly")
        }
        // Both cards as tall as the taller one.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Today · Day 5 · Day 7, annual trial only.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            step(Text("Today"), Text("Full UMEVA+, nothing charged"), isFirst: true, isLast: false)
            // The reminder is promised only when VESS may send one.
            step(Text("Day 5"), reminders.canRemind ? Text("We remind you the trial is ending") : Text("Cancel anytime in Settings before day 7"),
                 isFirst: false, isLast: false)
            step(Text("Day 7"), Text("\(price(.annual)) a year starts, unless you cancel"), isFirst: false, isLast: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plus.timeline")
    }

    private func step(_ title: Text, _ detail: Text, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: VESSSpacing.md) {
            VStack(spacing: 0) {
                Circle()
                    .fill(isFirst ? VESSColor.accent : VESSColor.borderStrong)
                    .frame(width: VESSSpacing.sm, height: VESSSpacing.sm)
                    .padding(.top, VESSSpacing.xxs + 2)
                if !isLast {
                    Rectangle()
                        .fill(VESSColor.borderStrong)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: VESSSpacing.sm)
            VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                title
                    .vessTextStyle(.bodyMStrong)
                    .foregroundStyle(VESSColor.text)
                detail
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : VESSSpacing.md)
        }
    }

    /// The button, the renewal text and the links.
    private var action: some View {
        VStack(spacing: VESSSpacing.sm) {
            Button(action: subscribe) {
                if isActivating {
                    Text("Activating…")
                } else if isSubscribed {
                    Text("You have UMEVA+")
                } else if hasTrial {
                    Text("Start 7-day free trial")
                } else if plan == .annual {
                    Text("Subscribe · \(price(.annual)) a year")
                } else {
                    Text("Subscribe · \(price(.monthly)) a month")
                }
            }
            .buttonStyle(.vessPrimary)
            .disabled(isWorking || isSubscribed)
            .accessibilityIdentifier("plus.subscribe")

            if !isSubscribed {
                Text(disclosure)
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = message ?? statusMessage {
                Text(message)
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            links
        }
        .frame(maxWidth: .infinity)
    }

    private var disclosure: LocalizedStringResource {
        if hasTrial {
            return "Free for 7 days, then \(price(.annual)) a year. Renews automatically unless you cancel at least 24 hours before the trial or the year ends. Cancel in Settings › Apple Account › Subscriptions."
        }
        return plan == .annual
            ? "\(price(.annual)) a year. Renews automatically unless you cancel at least 24 hours before the year ends. Cancel in Settings › Apple Account › Subscriptions."
            : "\(price(.monthly)) a month. Renews automatically unless you cancel at least 24 hours before the month ends. Cancel in Settings › Apple Account › Subscriptions."
    }

    /// "Compare Free and VESS+ · Terms of Use · Privacy", centred; stacked
    /// when they don't fit on one line.
    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VESSSpacing.md) { linkItems }
            VStack(spacing: 0) { linkItems }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var linkItems: some View {
        link("Compare Free and UMEVA+", isLink: false) { showCompare = true }
            .accessibilityIdentifier("plus.compare")
        if let url = Self.termsURL {
            link("Terms of Use") { openURL(url) }
        }
        link("Privacy Policy") {
            if let url = LegalLinks.privacyPolicy { openURL(url) } else { showPrivacy = true }
        }
        if isSubscribed {
            link("Manage subscription", isLink: false) { showManage = true }
        }
    }

    /// Terms of Use and Privacy Policy open web pages, so VoiceOver calls them links.
    private func link(_ title: LocalizedStringResource, isLink: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRemoveTraits(isLink ? .isButton : [])
        .accessibilityAddTraits(isLink ? .isLink : [])
    }

    private func select(_ option: Plan) {
        withAnimation(VESSMotion.selection) { plan = option }
    }

    // MARK: Prices

    private func price(_ option: Plan) -> String {
        if let product = products[option.productID] { return VESSFormat.groupThousands(product.displayPrice) }
        #if DEBUG
        return VESSFormat.groupThousands(option.fallbackPrice.formatted(.currency(code: "EUR")))
        #else
        // Never a price that isn't the App Store's.
        return "—"
        #endif
    }

    /// The price as shown: parsed from `displayPrice`, which StoreKit
    /// formats for the storefront, so the badge and the per-month line
    /// always agree with the big price.
    private func amount(_ option: Plan) -> Decimal {
        guard let product = products[option.productID] else { return option.fallbackPrice }
        return (try? Decimal(product.displayPrice, format: product.priceFormatStyle)) ?? product.price
    }

    /// "4,17 €": the annual price over 12 months, in the product's currency.
    private var monthlyEquivalent: String {
        let perMonth = amount(.annual) / 12
        if let product = products[Plan.annual.productID] {
            return perMonth.formatted(product.priceFormatStyle)
        }
        return perMonth.formatted(.currency(code: "EUR"))
    }

    /// "48": the saving against 12 monthly payments, rounded.
    private var savingPercent: String {
        let year = amount(.monthly) * 12
        guard year > 0 else { return "0" }
        let saving = (1 - NSDecimalNumber(decimal: amount(.annual) / year).doubleValue) * 100
        return saving.formatted(.number.precision(.fractionLength(0)))
    }

    // MARK: StoreKit

    private func load() async {
        if let loaded = try? await Product.products(for: Plan.allCases.map(\.productID)) {
            products = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        if let subscription = products[Plan.annual.productID]?.subscription {
            trialEligible = await subscription.isEligibleForIntroOffer
        }
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        // A real subscription only: a tester account's higher limits aren't one.
        let serverPlus = if case .plus = planStore.status { true } else { false }
        isSubscribed = await PlusStore.isEntitled() || serverPlus
    }

    /// The calm line for a purchase the server doesn't count yet.
    private var statusMessage: String? {
        switch planStore.status {
        case .activating: String(localized: "UMEVA+ is active. Updating your limits…")
        case .otherAccount: String(localized: "This UMEVA+ purchase belongs to another UMEVA account. Sign in with that account, or contact support.")
        case .free, .plus, .tester: nil
        }
    }

    private func subscribe() {
        // The purchase is tied to the account (appAccountToken), so the
        // server can check whose it is: signed out, sign in first.
        guard let userID = account.session.flatMap({ UUID(uuidString: $0.userID) }) else {
            continuesAfterSignIn = true
            showSignIn = true
            return
        }
        guard let product = products[plan.productID] else {
            message = String(localized: "Plans aren't available right now. Try again in a moment.")
            return
        }
        isWorking = true
        message = nil
        Task {
            defer { isWorking = false }
            do {
                switch try await PlusStore.purchase(product, accountToken: userID) {
                case .pending:
                    message = String(localized: "Waiting for approval. UMEVA+ starts as soon as it's approved.")
                case .cancelled:
                    break
                case .purchased(let transaction):
                    let isTrial = transaction.offer?.type == .introductory
                    var reminderAt: Date?
                    if isTrial {
                        reminderAt = await reminders.scheduleTrialReminder(trialStartedAt: transaction.purchaseDate,
                                                                           quiet: store.profile?.quietHours ?? .standard)
                    }
                    // "Activating…" until the server confirms, at most 5 s;
                    // B04 then shows, with its limits loading if need be.
                    isActivating = true
                    await confirmWithServer(timeout: 5)
                    isActivating = false
                    await refreshEntitlement()
                    if PlusWelcomeLedger().claim(transaction.originalID) {
                        welcome = PlusWelcome(id: transaction.originalID, isTrial: isTrial, endsAt: transaction.expirationDate,
                                              willAutoRenew: await willAutoRenew(product), reminderAt: reminderAt,
                                              limits: planStore.isPlus ? planStore.response?.limits : nil)
                    }
                }
            } catch PlusStore.PurchaseError.unverified {
                message = String(localized: "The App Store couldn't confirm the purchase. Try Restore in a moment.")
            } catch {
                message = String(localized: "The purchase didn't go through. Nothing was charged.")
            }
        }
    }

    /// Sends the purchase to the server and waits for its answer, at most
    /// `timeout` seconds (the plan store keeps retrying after that).
    private func confirmWithServer(timeout: TimeInterval) async {
        let store = planStore
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await store.sync() }
            group.addTask { try? await Task.sleep(for: .seconds(timeout)) }
            await group.next()
            group.cancelAll()
        }
    }

    /// From the renewal info; true when StoreKit can't say.
    private func willAutoRenew(_ product: Product) async -> Bool {
        guard let statuses = try? await product.subscription?.status else { return true }
        for status in statuses {
            if case .verified(let renewal) = status.renewalInfo, renewal.currentProductID == product.id {
                return renewal.willAutoRenew
            }
        }
        return true
    }

    /// Never shows B04: that's only for a new purchase.
    private func restore() {
        isWorking = true
        message = nil
        Task {
            defer { isWorking = false }
            do {
                let restored = try await PlusStore.restore()
                await planStore.sync()
                message = restored
                    ? (planStore.isPlus ? String(localized: "UMEVA+ is active again.") : statusMessage)
                    : String(localized: "No UMEVA+ subscription was found for this Apple Account.")
            } catch {
                message = String(localized: "Restore didn't go through. Try again in a moment.")
            }
            await refreshEntitlement()
        }
    }
}

/// Keeps the day-5 reminder only while the annual trial is running and set
/// to renew: it's removed once the trial has converted (the latest
/// transaction is no longer the introductory offer) or auto-renew is off.
enum VESSPlusTrial {
    static func reconcileReminder(_ reminders: ReminderService) async {
        if await !isTrialRenewing() { reminders.cancelTrialReminder() }
    }

    static func isTrialRenewing() async -> Bool {
        guard let product = try? await Product.products(for: [VESSPlusView.Plan.annual.productID]).first,
              let statuses = try? await product.subscription?.status else { return false }
        for status in statuses {
            guard status.state == .subscribed,
                  case .verified(let renewal) = status.renewalInfo,
                  case .verified(let transaction) = status.transaction else { continue }
            if transaction.offer?.type == .introductory && renewal.willAutoRenew { return true }
        }
        return false
    }
}

/// "Compare Free and VESS+": the limits side by side.
private struct VESSPlusComparison: View {
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let title: LocalizedStringResource
        let free: String
        let plus: String
        var id: String { "\(title)" }
    }

    private var rows: [Row] {
        [
            Row(title: "AI Coach", free: perDay(\.coachQuestions, UMEVAPlusLimits.free), plus: perDay(\.coachQuestions, UMEVAPlusLimits.plus)),
            Row(title: "Photo and menu estimates", free: perDay(\.photoEstimates, UMEVAPlusLimits.free), plus: perDay(\.photoEstimates, UMEVAPlusLimits.plus)),
            Row(title: "AI Chef recipes", free: perDay(\.chefRecipes, UMEVAPlusLimits.free), plus: perDay(\.chefRecipes, UMEVAPlusLimits.plus)),
            Row(title: "Insights history", free: String(localized: "\(UMEVAPlusLimits.freeInsightsDays) days"), plus: String(localized: "All")),
            Row(title: "Health patterns", free: "—", plus: "✓"),
            Row(title: "Logging, recipes, pantry, grocery, Apple Health", free: "✓", plus: "✓"),
        ]
    }

    private func perDay(_ limit: KeyPath<UMEVAPlusLimits.Tier, Int>, _ tier: UMEVAPlusLimits.Tier) -> String {
        String(localized: "\(tier[keyPath: limit]) a day")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    HStack {
                        Spacer()
                        Text("Free").frame(minWidth: 64, alignment: .trailing)
                        Text("UMEVA+").frame(minWidth: 64, alignment: .trailing)
                    }
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.tertiaryText)
                    VESSRowGroup {
                        ForEach(rows) { row in
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Text(row.title).foregroundStyle(VESSColor.text)
                                    Spacer(minLength: VESSSpacing.sm)
                                    Text(verbatim: row.free).frame(minWidth: 64, alignment: .trailing).foregroundStyle(VESSColor.secondaryText)
                                    Text(verbatim: row.plus).frame(minWidth: 64, alignment: .trailing).foregroundStyle(VESSColor.text)
                                }
                                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                                    Text(row.title).foregroundStyle(VESSColor.text)
                                    Text("Free \(row.free) · UMEVA+ \(row.plus)").foregroundStyle(VESSColor.secondaryText)
                                }
                            }
                            .vessTextStyle(.bodyM)
                            .padding(.vertical, VESSSpacing.sm)
                            .frame(maxWidth: .infinity, minHeight: VESSSize.rowHeight, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(row.title))
                            .accessibilityValue(Text("Free: \(row.free). UMEVA+: \(row.plus)"))
                        }
                    }
                    .vessHairlineBottom()
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .vessContentTop(VESSSpacing.md)
            }
            .background(VESSColor.card)
            .vessDetailTitle("Free and UMEVA+")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(VESSRadius.sheet)
    }
}
