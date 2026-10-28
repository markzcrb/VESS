import StoreKit
import SwiftUI

/// What B04 shows, read from the verified purchase.
struct PlusWelcome: Identifiable, Equatable {
    /// The subscription's `originalID`: B04 shows once per subscription.
    let id: UInt64
    /// In the introductory offer (the free week).
    let isTrial: Bool
    /// When the trial ends, or the next renewal.
    let endsAt: Date?
    let willAutoRenew: Bool
    /// When the trial reminder is scheduled; `nil` when it isn't.
    let reminderAt: Date?
}

/// B04 is shown once per subscription (`originalTransactionID`), never on
/// restore. Remembers which ones it has welcomed.
struct PlusWelcomeLedger {
    private let defaults: UserDefaults
    static let key = "plus.welcomedOriginalIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True the first time for `originalID`, then false.
    func claim(_ originalID: UInt64) -> Bool {
        var welcomed = defaults.stringArray(forKey: Self.key) ?? []
        let id = String(originalID)
        guard !welcomed.contains(id) else { return false }
        welcomed.append(id)
        defaults.set(welcomed, forKey: Self.key)
        return true
    }
}

/// B04, right after a verified UMEVA+ purchase: always graphite silk, the
/// state, the dates from the transaction, the real limits
/// (`UMEVAPlusLimits`), Ask Coach something, Done, and Manage.
struct PlusWelcomeView: View {
    let welcome: PlusWelcome
    let onAskCoach: () -> Void
    let onDone: () -> Void

    @State private var showManage = false

    var body: some View {
        BrandScreenLayout {
            UMEVAWordmark(width: UMEVAWordmark.headerWidth)
                .foregroundStyle(VESSColor.text)
                .padding(.top, VESSSpacing.xxl)
        } bottom: {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text(welcome.isTrial ? "UMEVA+ · Trial active" : "UMEVA+ · Active")
                        .vessTextStyle(.labelCaps)
                        .foregroundStyle(VESSColor.secondaryText)
                    Text("Welcome to UMEVA+.")
                        .vessTextStyle(.editorialL)
                        .foregroundStyle(VESSColor.text)
                        .accessibilityAddTraits(.isHeader)
                    detail
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.secondaryText)
                        .padding(.top, VESSSpacing.xxs)
                }
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: VESSSpacing.md) {
                    let plus = UMEVAPlusLimits.plus
                    check(Text("\(plus.coachQuestions) Coach questions a day, with charts"))
                    check(Text("\(plus.photoEstimates) photo and menu estimates a day"))
                    check(Text("\(plus.chefRecipes) AI Chef recipes a day"))
                    check(Text("All insights and Health patterns"))
                }

                VStack(spacing: VESSSpacing.xs) {
                    Button("Ask Coach something", action: onAskCoach)
                        .buttonStyle(.vessPrimary)
                        .accessibilityIdentifier("plusWelcome.coach")
                    Button("Done", action: onDone)
                        .buttonStyle(.brandText)
                        .accessibilityIdentifier("plusWelcome.done")
                    Button { showManage = true } label: {
                        Text("Manage or cancel any time in Settings.")
                            .vessTextStyle(.caption)
                            .foregroundStyle(VESSColor.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: VESSHitTarget.minimum)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens your subscriptions"))
                    .accessibilityIdentifier("plusWelcome.manage")
                }
            }
        }
        .background {
            BrandSilkBackground(image: VESSBrandAssets.silkGraphite, base: VESSColor.brandGraphite, coverage: 0.55)
        }
        .manageSubscriptionsSheet(isPresented: $showManage)
        // Graphite in both appearances, so every token resolves dark.
        .environment(\.colorScheme, .dark)
    }

    private var detail: Text {
        let date = welcome.endsAt.map { $0.formatted(.dateTime.day().month(.wide)) }
        if welcome.isTrial, let date {
            if let reminder = welcome.reminderAt {
                return Text("Everything is unlocked. Your free week runs until \(date); we'll remind you on \(reminder.formatted(.dateTime.day().month(.wide))).")
            }
            return Text("Everything is unlocked. Your free week runs until \(date).")
        }
        if let date {
            return welcome.willAutoRenew
                ? Text("Everything is unlocked. It renews on \(date).")
                : Text("Everything is unlocked until \(date).")
        }
        return Text("Everything is unlocked.")
    }

    private func check(_ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.sm) {
            Image(systemName: "checkmark")
                .font(.body.weight(.medium))
                .foregroundStyle(VESSColor.text)
                .accessibilityHidden(true)
            text
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("B04 Trial") {
    PlusWelcomeView(welcome: PlusWelcome(id: 1, isTrial: true, endsAt: .now.addingTimeInterval(7 * 86_400), willAutoRenew: true,
                                         reminderAt: .now.addingTimeInterval(5 * 86_400)),
                    onAskCoach: {}, onDone: {})
}

#Preview("B04 Active") {
    PlusWelcomeView(welcome: PlusWelcome(id: 1, isTrial: false, endsAt: .now.addingTimeInterval(365 * 86_400), willAutoRenew: true, reminderAt: nil),
                    onAskCoach: {}, onDone: {})
        .preferredColorScheme(.light)
}
