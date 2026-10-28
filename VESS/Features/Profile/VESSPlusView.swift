#if DEBUG
import StoreKit
import SwiftUI

/// P02 VESS+: what it adds, two plans side by side (Annual preselected with
/// its 7-day trial and the trial timeline; Monthly without a trial), the
/// required subscription text, and Free vs VESS+ in a sheet. Prices come
/// from StoreKit (`displayPrice`); the euro values are DEBUG fallbacks.
/// On small screens the button and its text stay pinned at the bottom once
/// the page has been scrolled with the plans fully on screen and the
/// button not yet (not at accessibility sizes, where the bar would fill
/// the screen).
/// DEBUG only.
struct VESSPlusView: View {
    enum Plan: String, CaseIterable, Identifiable {
        case monthly, annual
        var id: String { rawValue }

        /// "<bundle id>.plus.monthly" / ".plus.annual" (App Store Connect
        /// and VESS.storekit for local testing).
        var productID: String {
            let bundle = Bundle.main.bundleIdentifier ?? "com.markgerasimovpersonalteam.VESS"
            switch self {
            case .monthly: return "\(bundle).plus.monthly"
            case .annual: return "\(bundle).plus.annual"
            }
        }

        /// DEBUG fallbacks when StoreKit has no product.
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
    @State private var plan: Plan = .annual
    @State private var products: [String: Product] = [:]
    /// Whether the annual trial can still be offered (StoreKit says).
    @State private var trialEligible = true
    @State private var isSubscribed = false
    @State private var isWorking = false
    @State private var showManage = false
    @State private var showCompare = false
    @State private var showPrivacy = false
    @State private var message: String?
    /// For the pinned button: the viewport's height, the plans' top and the
    /// in-page button's bottom, in the scroll view's coordinates.
    @State private var viewportHeight: CGFloat = 0
    @State private var plansBottom: CGFloat = .greatestFiniteMagnitude
    @State private var buttonBottom: CGFloat = 0
    @State private var hasScrolled = false

    /// Apple's standard licence agreement (Terms of Use).
    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    private var hasTrial: Bool { plan == .annual && trialEligible }
    private var pinsButton: Bool {
        !dynamicTypeSize.isAccessibilitySize && !isSubscribed && hasScrolled
            && plansBottom <= viewportHeight && buttonBottom > viewportHeight
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                    header
                    features
                    plans
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).maxY } action: { plansBottom = $0 }
                    if hasTrial { timeline }
                    action
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).maxY } action: { buttonBottom = $0 }
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .padding(.top, VESSSpacing.xs)
                .padding(.bottom, VESSSpacing.xl)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in viewportHeight = height }
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, scrolled in
                if scrolled { hasScrolled = true }
            }
            // Content never shows through under Close and Restore.
            .scrollEdgeEffectStyle(.hard, for: .top)
            .background(VESSColor.background)
            // An overlay, not an inset: the scroll view's size stays the same,
            // so showing the bar can't change whether it should show.
            .overlay(alignment: .bottom) {
                if pinsButton {
                    action
                        .padding(.horizontal, VESSSpacing.screenInset)
                        .padding(.vertical, VESSSpacing.sm)
                        .background(VESSColor.background.ignoresSafeArea(edges: .bottom))
                        .overlay(alignment: .top) { VESSHairline() }
                        .transition(.opacity)
                }
            }
            .animation(VESSMotion.selection, value: pinsButton)
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
            .sheet(isPresented: $showCompare) { VESSPlusComparison() }
            .manageSubscriptionsSheet(isPresented: $showManage)
        }
        .task { await load() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            Text("VESS+")
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
            VESSFeatureRow(systemImage: "bubble.left", title: Text("AI Coach"),
                           detail: Text("15 questions a day, with charts from your own data"))
            VESSFeatureRow(systemImage: "camera", title: Text("Photo and menu estimates"),
                           detail: Text("10 a day: your plate or a restaurant menu"))
            VESSFeatureRow(systemImage: "fork.knife", title: Text("AI Chef"),
                           detail: Text("5 recipes a day from what's in your pantry"))
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
                detail: Text("\(monthlyEquivalent) a month, billed yearly"),
                badge: Text(verbatim: "\u{2212}\(savingPercent)\u{00A0}%"),
                isSelected: plan == .annual
            ) { select(.annual) }
            .accessibilityIdentifier("plus.plan.annual")
            VESSPlanCard(
                title: "Monthly", price: Text(verbatim: price(.monthly)),
                detail: Text("a month · cancel anytime"),
                isSelected: plan == .monthly
            ) { select(.monthly) }
            .accessibilityIdentifier("plus.plan.monthly")
        }
    }

    /// Today · Day 5 · Day 7, annual trial only.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            step(Text("Today"), Text("Full VESS+, nothing charged"), isFirst: true, isLast: false)
            step(Text("Day 5"), Text("We remind you the trial is ending"), isFirst: false, isLast: false)
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
                if isSubscribed {
                    Text("You have VESS+")
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
            if let message {
                Text(message)
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.warningText)
                    .multilineTextAlignment(.center)
            }
            links
        }
        .frame(maxWidth: .infinity)
    }

    private var disclosure: LocalizedStringResource {
        if hasTrial {
            return "Then \(price(.annual)) a year. Renews automatically until you cancel, at least 24 hours before the renewal date, in Settings › Apple Account › Subscriptions."
        }
        return plan == .annual
            ? "\(price(.annual)) a year. Renews automatically until you cancel, at least 24 hours before the renewal date, in Settings › Apple Account › Subscriptions."
            : "\(price(.monthly)) a month. Renews automatically until you cancel, at least 24 hours before the renewal date, in Settings › Apple Account › Subscriptions."
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
        link("Compare Free and VESS+") { showCompare = true }
            .accessibilityIdentifier("plus.compare")
        if let url = Self.termsURL {
            link("Terms of Use") { openURL(url) }
        }
        link("Privacy") { showPrivacy = true }
        if isSubscribed {
            link("Manage subscription") { showManage = true }
        }
    }

    private func link(_ title: LocalizedStringResource, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.secondaryText)
                .multilineTextAlignment(.center)
                .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ option: Plan) {
        withAnimation(VESSMotion.selection) { plan = option }
    }

    // MARK: Prices

    private func price(_ option: Plan) -> String {
        VESSFormat.groupThousands(products[option.productID]?.displayPrice ?? option.fallbackPrice.formatted(.currency(code: "EUR")))
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
        var subscribed = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Plan.allCases.map(\.productID).contains(transaction.productID) {
                subscribed = true
            }
        }
        isSubscribed = subscribed
    }

    private func subscribe() {
        guard let product = products[plan.productID] else {
            message = String(localized: "Plans aren't available in this build yet.")
            return
        }
        isWorking = true
        message = nil
        Task {
            defer { isWorking = false }
            do {
                if case .success(let verification) = try await product.purchase(), case .verified(let transaction) = verification {
                    await transaction.finish()
                    if transaction.offer?.type == .introductory {
                        await reminders.scheduleTrialReminder(trialStartedAt: transaction.purchaseDate)
                    }
                    await refreshEntitlement()
                }
            } catch {
                message = String(localized: "The purchase didn't go through. Nothing was charged.")
            }
        }
    }

    private func restore() {
        isWorking = true
        Task {
            defer { isWorking = false }
            try? await AppStore.sync()
            await refreshEntitlement()
        }
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
            Row(title: "AI Coach", free: String(localized: "3 a day"), plus: String(localized: "15 a day")),
            Row(title: "Photo and menu estimates", free: String(localized: "1 a day"), plus: String(localized: "10 a day")),
            Row(title: "AI Chef recipes", free: String(localized: "1 a day"), plus: String(localized: "5 a day")),
            Row(title: "Insights history", free: String(localized: "30 days"), plus: String(localized: "All")),
            Row(title: "Health patterns", free: "—", plus: "✓"),
            Row(title: "Logging, recipes, pantry, grocery, Apple Health", free: "✓", plus: "✓"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    HStack {
                        Spacer()
                        Text("Free").frame(minWidth: 64, alignment: .trailing)
                        Text("VESS+").frame(minWidth: 64, alignment: .trailing)
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
                                    Text("Free \(row.free) · VESS+ \(row.plus)").foregroundStyle(VESSColor.secondaryText)
                                }
                            }
                            .vessTextStyle(.bodyM)
                            .padding(.vertical, VESSSpacing.sm)
                            .frame(maxWidth: .infinity, minHeight: VESSSize.rowHeight, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(row.title))
                            .accessibilityValue(Text("Free: \(row.free). VESS+: \(row.plus)"))
                        }
                    }
                    .vessHairlineBottom()
                }
                .padding(.horizontal, VESSSpacing.screenInset)
                .vessContentTop(VESSSpacing.md)
            }
            .background(VESSColor.card)
            .vessDetailTitle("Free and VESS+")
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
#endif
