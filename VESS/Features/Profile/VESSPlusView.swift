#if DEBUG
import StoreKit
import SwiftUI

/// E08 VESS+. Two plans (annual preselected, 7-day trial on annual only),
/// what free and VESS+ include, and the required subscription text. Prices
/// come from StoreKit (`displayPrice`); the euro values are DEBUG fallbacks
/// until the products exist. DEBUG only: Release has no row for it yet.
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

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var plan: Plan = .annual
    @State private var products: [String: Product] = [:]
    @State private var isSubscribed = false
    @State private var isWorking = false
    @State private var showManage = false
    @State private var message: String?

    /// Apple's standard licence agreement (Terms of Use).
    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    var body: some View {
        ProfilePage(title: "VESS+") {
            ProfileIntro(title: "Coach, Chef and photo estimates, every day.",
                         text: "Logging, recipes, pantry, grocery and Apple Health stay free.")

            VStack(spacing: VESSSpacing.sm) {
                ForEach([Plan.annual, .monthly]) { option in
                    planCard(option)
                }
            }

            comparison

            VStack(alignment: .leading, spacing: VESSSpacing.sm) {
                Button(action: subscribe) {
                    Text(plan == .annual ? "Start 7-day free trial" : "Subscribe")
                }
                .buttonStyle(.vessPrimary)
                .disabled(isWorking || isSubscribed)
                .accessibilityIdentifier("plus.subscribe")
                Text(plan == .annual
                     ? "7 days free, then \(price(.annual))/year. Cancel anytime."
                     : "\(price(.monthly))/month. Cancel anytime.")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.warningText)
                }
            }

            legal
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
        .task { await load() }
    }

    // MARK: Plans

    private func planCard(_ option: Plan) -> some View {
        let isSelected = option == plan
        let shape = RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
        return Button { plan = option } label: {
            HStack(alignment: .top, spacing: VESSSpacing.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? VESSColor.accent : VESSColor.tertiaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                    // Stacked at accessibility sizes, so no word splits.
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.xxs))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                    layout {
                        Text(option == .annual ? "Annual" : "Monthly")
                            .vessTextStyle(.bodyMStrong)
                            .foregroundStyle(VESSColor.text)
                        if option == .annual {
                            VESSTag(text: Text("7 days free"), tone: .accent)
                        }
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: VESSSpacing.xs) }
                        Text(option == .annual ? "\(price(.annual))/year" : "\(price(.monthly))/month")
                            .vessTextStyle(.bodyM)
                            .foregroundStyle(VESSColor.text)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if option == .annual {
                        Text("\(monthlyEquivalent)/month · save \(savingPercent)\u{00A0}%")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                    }
                }
            }
            .padding(VESSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? VESSColor.tintLink : VESSColor.card, in: shape)
            .overlay(shape.strokeBorder(isSelected ? VESSColor.strokeLink : VESSColor.divider, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("plus.plan.\(option.rawValue)")
    }

    // MARK: Free vs VESS+

    private struct Row: Identifiable {
        let title: LocalizedStringResource
        let free: String
        let plus: String
        var id: String { "\(title)" }
    }

    private var rows: [Row] {
        [
            Row(title: "AI Coach", free: String(localized: "3 a day"), plus: String(localized: "15 a day")),
            Row(title: "Meal photo estimates", free: String(localized: "1 a day"), plus: String(localized: "10 a day")),
            Row(title: "AI Chef recipes", free: String(localized: "1 a day"), plus: String(localized: "5 a day")),
            Row(title: "Insights history", free: String(localized: "30 days"), plus: String(localized: "All")),
            Row(title: "Health patterns", free: "—", plus: "✓"),
        ]
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xs) {
            HStack {
                Text("Free vs VESS+")
                    .vessTextStyle(.labelCaps)
                    .foregroundStyle(VESSColor.secondaryText)
                    .accessibilityAddTraits(.isHeader)
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
                            Text(row.title).vessTextStyle(.bodyM).foregroundStyle(VESSColor.text)
                            Spacer(minLength: VESSSpacing.sm)
                            Text(verbatim: row.free).frame(minWidth: 64, alignment: .trailing).foregroundStyle(VESSColor.secondaryText)
                            Text(verbatim: row.plus).frame(minWidth: 64, alignment: .trailing).foregroundStyle(VESSColor.text)
                        }
                        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
                            Text(row.title).vessTextStyle(.bodyM).foregroundStyle(VESSColor.text)
                            Text("Free \(row.free) · VESS+ \(row.plus)").foregroundStyle(VESSColor.secondaryText)
                        }
                    }
                    .vessTextStyle(.bodyM)
                    .padding(.vertical, VESSSpacing.sm)
                    .frame(minHeight: VESSSize.rowHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(row.title))
                    .accessibilityValue(Text("Free: \(row.free). VESS+: \(row.plus)"))
                }
            }
            .vessHairlineBottom()
        }
    }

    // MARK: Required text

    private var legal: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            ActivityFootnote(text: Text("Payment is charged to your Apple Account when you confirm (after the free trial, for the annual plan). The subscription renews automatically at the same price unless you cancel at least 24 hours before the end of the period. Manage or cancel in Settings › Apple Account › Subscriptions."))
            HStack(spacing: VESSSpacing.lg) {
                if let url = Self.termsURL {
                    Button("Terms of Use") { openURL(url) }
                        .buttonStyle(.vessQuiet)
                }
                NavigationLink(value: ProfileRoute.privacy) {
                    Text("Privacy Policy")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.accent)
                        .padding(.vertical, VESSSpacing.sm)
                        .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: VESSSpacing.lg) {
                Button("Restore purchases", action: restore)
                    .buttonStyle(.vessQuiet)
                    .disabled(isWorking)
                if isSubscribed {
                    Button("Manage subscription") { showManage = true }
                        .buttonStyle(.vessQuiet)
                }
            }
        }
    }

    // MARK: Prices

    private func price(_ option: Plan) -> String {
        products[option.productID]?.displayPrice ?? option.fallbackPrice.formatted(.currency(code: "EUR"))
    }

    private func amount(_ option: Plan) -> Decimal {
        products[option.productID]?.price ?? option.fallbackPrice
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
#endif
