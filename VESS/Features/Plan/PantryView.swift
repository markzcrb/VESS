import SwiftUI

/// C01: what's at home. Items to use in the next few days first, then the
/// rest by where it's kept. C04 when empty.
struct PantryView: View {
    @Environment(LocalStore.self) private var store

    @State private var addRequest: AddPantryRequest?
    @State private var showScanner = false
    @State private var scanned: Food?

    private let calendar = Calendar.current

    var body: some View {
        let now = AppClock.now
        let overview = PantryOverview(items: store.inventory, now: now, calendar: calendar)

        ScrollView {
            Group {
                if overview.totalCount == 0 {
                    emptyState
                } else {
                    content(overview, now: now)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.top, VESSSpacing.xs)
            .padding(.bottom, VESSSpacing.huge)
        }
        .vessScreenBackground()
        .vessDetailTitle("Pantry")
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $addRequest) { request in
            AddPantryItemSheet(product: request.product)
        }
        .fullScreenCover(isPresented: $showScanner, onDismiss: {
            // A scanned product opens Add with its name filled in.
            if let scanned { addRequest = AddPantryRequest(product: scanned) }
            scanned = nil
        }) {
            BarcodeScannerView(
                day: now,
                meal: .constant(.dinner),
                onLogged: { showScanner = false },
                onTypeNumber: { showScanner = false; addRequest = AddPantryRequest() },
                onAddManually: { _ in showScanner = false; addRequest = AddPantryRequest() },
                onProduct: { scanned = $0 }
            )
        }
    }

    // MARK: Sections

    private func content(_ overview: PantryOverview, now: Date) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.section) {
            VStack(alignment: .leading, spacing: VESSSpacing.md) {
                Text("^[\(overview.totalCount) item](inflect: true) at home")
                    .vessTextStyle(.editorialL)
                    .foregroundStyle(VESSColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(overview.useSoon.isEmpty
                     ? "Nothing needs using in the next few days."
                     : "\(overview.useSoon.count) to use in the next few days.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                VStack(spacing: VESSSpacing.sm) {
                    addButtons(primary: false)
                }
                .padding(.top, VESSSpacing.xs)
            }

            if !overview.useSoon.isEmpty {
                section(
                    title: Text("Use soon · ^[\(overview.useSoon.count) item](inflect: true)"),
                    items: overview.useSoon,
                    showsLocation: true,
                    now: now
                )
            }

            ForEach(overview.groups, id: \.location) { group in
                section(
                    title: Text("\(Text(group.location.title)) · \(group.items.count)"),
                    items: group.items,
                    showsLocation: false,
                    now: now
                )
            }
        }
    }

    private func section(title: Text, items: [InventoryItem], showsLocation: Bool, now: Date) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            title
                .vessTextStyle(.labelCaps)
                .foregroundStyle(VESSColor.secondaryText)
                .accessibilityAddTraits(.isHeader)
            VESSRowGroup {
                ForEach(items) { item in
                    NavigationLink {
                        PantryItemView(itemID: item.id)
                    } label: {
                        VESSRow(
                            title: Text(item.name),
                            subtitle: showsLocation ? item.placeAndQuantity : Text(item.quantityText)
                        ) {
                            pantryExpiryText(for: item, now: now, calendar: calendar)
                                .vessTextStyle(.bodyM)
                                .foregroundStyle(VESSColor.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pantry.\(item.name)")
                }
            }
            .vessHairlineBottom()
        }
    }

    /// C04.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            Text("Your pantry is empty")
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .accessibilityAddTraits(.isHeader)
            Text("Add what you have at home, or check off groceries and tap Done shopping to move them here.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: VESSSpacing.sm) {
                addButtons(primary: true)
            }
            .padding(.top, VESSSpacing.xs)
        }
        .padding(.top, VESSSpacing.huge * 2)
    }

    @ViewBuilder
    private func addButtons(primary: Bool) -> some View {
        Button("Add item") { addRequest = AddPantryRequest() }
            .buttonStyle(primary ? .vessPrimary : .vessSecondary)
            .accessibilityIdentifier("pantry.add")
        Button("Scan barcode") { showScanner = true }
            .buttonStyle(.vessSecondary)
            .accessibilityIdentifier("pantry.scan")
    }
}

/// Opens Add to pantry, optionally with a scanned product.
private struct AddPantryRequest: Identifiable {
    let id = UUID()
    var product: Food?
}

#Preview("Pantry") {
    NavigationStack { PantryView() }
        .previewEnvironment(LocalStore.preview())
}

#Preview("Empty") {
    NavigationStack { PantryView() }
        .previewEnvironment(LocalStore.preview(.profileOnly))
}
