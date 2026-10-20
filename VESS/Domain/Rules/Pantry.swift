import Foundation

/// The Pantry overview (C01): items to use soon first, then everything else
/// by where it's stored. Built on `ExpirationStatus` (3-day threshold).
/// Pure and deterministic.
nonisolated struct PantryOverview: Sendable {
    struct Group: Sendable {
        let location: StorageLocation
        let items: [InventoryItem]
    }

    /// Expired, today, tomorrow or within `ExpirationStatus.soonThresholdDays`,
    /// soonest first.
    let useSoon: [InventoryItem]
    /// The rest, by location (fridge, freezer, cupboard, counter), soonest
    /// first, undated last. Empty locations are left out.
    let groups: [Group]
    let totalCount: Int

    init(items: [InventoryItem], now: Date, calendar: Calendar) {
        let available = items.filter { $0.status == .available }.sorted(by: Self.soonestFirst)
        let soon = available.filter { $0.expirationStatus(now: now, calendar: calendar).needsAttention }
        let soonIDs = Set(soon.map(\.id))
        let rest = available.filter { !soonIDs.contains($0.id) }

        useSoon = soon
        groups = StorageLocation.allCases.compactMap { location in
            let items = rest.filter { $0.location == location }
            return items.isEmpty ? nil : Group(location: location, items: items)
        }
        totalCount = available.count
    }

    /// Dated before undated; earlier dates first; then by name.
    static func soonestFirst(_ lhs: InventoryItem, _ rhs: InventoryItem) -> Bool {
        switch (lhs.expirationDate, rhs.expirationDate) {
        case let (left?, right?) where left != right: left < right
        case (.some, nil): true
        case (nil, .some): false
        default: lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Quick expiry choices on the pantry item and add screens (C02, C03).
nonisolated enum ExpiryPreset: CaseIterable, Identifiable, Sendable {
    case today, tomorrow, inThreeDays, inAWeek, inAMonth, noDate

    var id: Self { self }

    /// Days from today, or `nil` for no date.
    var days: Int? {
        switch self {
        case .today: 0
        case .tomorrow: 1
        case .inThreeDays: 3
        case .inAWeek: 7
        case .inAMonth: 30
        case .noDate: nil
        }
    }

    /// The expiry date for this choice: the start of that day.
    func date(from now: Date, calendar: Calendar) -> Date? {
        guard let days else { return nil }
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
    }

    /// The choice that matches `date` exactly, or `nil` for any other date.
    static func matching(_ date: Date?, now: Date, calendar: Calendar) -> ExpiryPreset? {
        guard let date else { return .noDate }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day
        return allCases.first { $0.days != nil && $0.days == days }
    }
}
