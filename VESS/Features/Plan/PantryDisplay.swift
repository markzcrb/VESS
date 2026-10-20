import SwiftUI

extension InventoryItem {
    /// "150 g", "1 kg", or a plain count for pieces ("2").
    var quantityText: String {
        switch unit {
        case .piece: VESSFormat.quantity(quantity)
        default: "\(VESSFormat.quantity(quantity)) \(String(localized: unit.abbreviation))"
        }
    }

    /// "Fridge · 150 g".
    var placeAndQuantity: Text {
        Text("\(Text(location.title)) · \(quantityText)")
    }
}

extension ExpirationStatus {
    /// Calm, relative wording for Use soon: "Today", "Tomorrow", "In 2 days",
    /// "Expired yesterday". Never red.
    var relativeText: Text? {
        switch self {
        case .noDate: nil
        case .expired(let days): days == 1 ? Text("Expired yesterday") : Text("Expired \(days) days ago")
        case .today: Text("Today")
        case .tomorrow: Text("Tomorrow")
        case .soon(let days), .later(let days): Text("In \(days) days")
        }
    }
}

/// The trailing expiry on a pantry row: relative when soon, a date when
/// later ("10 Oct"), "No date" without one.
func pantryExpiryText(for item: InventoryItem, now: Date, calendar: Calendar) -> Text {
    let status = item.expirationStatus(now: now, calendar: calendar)
    if status.needsAttention, let relative = status.relativeText { return relative }
    guard let date = item.expirationDate else { return Text("No date") }
    if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
        return Text(date, format: .dateTime.day().month(.abbreviated).year())
    }
    return Text(date, format: .dateTime.day().month(.abbreviated))
}

extension ExpiryPreset {
    var title: LocalizedStringResource {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .inThreeDays: "In 3 days"
        case .inAWeek: "In a week"
        case .inAMonth: "In a month"
        case .noDate: "No date"
        }
    }
}

/// STORED IN: one chip per location.
struct StorageLocationChips: View {
    @Binding var location: StorageLocation

    var body: some View {
        VESSChipFlow {
            ForEach(StorageLocation.allCases, id: \.self) { option in
                VESSChip(title: option.title, isSelected: location == option) {
                    location = option
                }
            }
        }
    }
}

/// EXPIRES / USE BY: preset chips. A date that matches no preset leaves
/// every chip unselected.
struct ExpiryChips: View {
    @Binding var date: Date?
    var presets: [ExpiryPreset] = ExpiryPreset.allCases
    let now: Date
    let calendar: Calendar

    var body: some View {
        let selected = ExpiryPreset.matching(date, now: now, calendar: calendar)
        VESSChipFlow {
            ForEach(presets) { preset in
                VESSChip(title: preset.title, isSelected: selected == preset) {
                    date = preset.date(from: now, calendar: calendar)
                }
            }
        }
    }
}
