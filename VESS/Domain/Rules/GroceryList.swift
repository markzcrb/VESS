import Foundation

/// Where an item is in a shop. "Fish" replaces the design's "Meat & fish"
/// (DATA.md overrides).
nonisolated enum GroceryAisle: String, Codable, CaseIterable, Sendable {
    case produce, fish, dairyEggs, bakery, pantryStaples, other

    /// A first guess from the item's name, from a small fixed word list.
    /// The user can change it per item; unknown names go to `.other`.
    static func guess(for name: String) -> GroceryAisle {
        let words = Set(FoodSearch.normalized(name).split(separator: " ").map(String.init))
        for (aisle, keywords) in keywordTable where !words.isDisjoint(with: keywords) {
            return aisle
        }
        return .other
    }

    private static let keywordTable: [(GroceryAisle, Set<String>)] = [
        (.fish, ["salmon", "cod", "fish", "prawn", "prawns", "tuna", "trout", "mackerel", "haddock", "shrimp", "seafood"]),
        (.dairyEggs, ["milk", "yogurt", "yoghurt", "skyr", "cheese", "butter", "cream", "egg", "eggs", "feta", "kefir"]),
        (.bakery, ["bread", "rye", "wrap", "wraps", "tortilla", "tortillas", "bagel", "sourdough", "pitta", "rolls"]),
        (.pantryStaples, ["pasta", "rice", "beans", "lentils", "chickpeas", "oil", "miso", "mirin", "honey", "oats", "flour", "stock", "sauce", "tin", "noodles"]),
        (.produce, [
            "broccoli", "cucumber", "potato", "potatoes", "tomato", "tomatoes", "cabbage", "lime", "limes", "lemon", "lemons",
            "basil", "spinach", "choy", "onion", "onions", "carrot", "carrots", "apple", "apples", "banana", "bananas",
            "berries", "blueberries", "pepper", "peppers", "garlic", "ginger", "avocado", "lettuce", "herbs", "parsley",
            "coriander", "courgette", "mushrooms", "greens", "kale", "leek", "celery",
        ]),
    ]
}

/// Something on the grocery list that the user added or changed. Lines
/// that come from the plan are recomputed each time; this only keeps what
/// the user said about them (checked, aisle, amount, "I already have it").
nonisolated struct GroceryItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// `GroceryList.key(for:)` of the name, to match plan lines.
    var key: String
    var name: String
    /// For manual items, the amount; for plan lines, an override.
    var quantity: Double?
    var unit: QuantityUnit?
    /// An aisle the user chose; `nil` uses the guess.
    var aisle: GroceryAisle?
    var isChecked: Bool
    /// Added by the user rather than from the plan.
    var isManual: Bool
    /// "I already have it" or "Remove from list" on a plan line.
    var isDismissed: Bool
    let createdAt: Date
}

/// The grocery list (PRODUCT-LOGIC.md #10, decided 2026-10-20): ingredients
/// of meals planned from today through the end of the week, minus what's
/// in the pantry, plus items added by the user. Checking an item never
/// stores it; only Done shopping moves checked items into the pantry.
/// Pure and deterministic.
nonisolated struct GroceryList: Sendable {
    nonisolated struct Line: Identifiable, Sendable {
        let key: String
        let name: String
        let quantity: Double?
        let unit: QuantityUnit?
        let aisle: GroceryAisle
        let isChecked: Bool
        let isManual: Bool
        /// The planned meals that need it (empty for manual items).
        let meals: [PlannedMeal]
        /// The stored state for this line, if any.
        let state: GroceryItem?

        var id: String { key }
    }

    /// Unchecked first, then checked; each by aisle order, then name.
    let lines: [Line]
    /// Plan ingredients left off because they're at home.
    let leftOffCount: Int
    /// Planned meals the list was built from.
    let plannedMealCount: Int

    var toBuy: [Line] { lines.filter { !$0.isChecked } }
    var checked: [Line] { lines.filter(\.isChecked) }

    static func key(for name: String) -> String {
        FoodSearch.normalized(name)
    }

    /// - Parameters:
    ///   - start: today; earlier planned days are left out.
    ///   - end: the end of the week (exclusive).
    ///   - states: what the user added or changed. A plan line's state only
    ///     counts in the week it was made, so a new week starts fresh.
    init(planned: [PlannedMeal], pantry: [InventoryItem], states: [GroceryItem], from start: Date, to end: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: start)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? today
        let meals = planned.filter { $0.loggedAt == nil && $0.day >= today && $0.day < end }
        let current = states.filter { $0.isManual || $0.createdAt >= weekStart }
        let statesByKey = Dictionary(current.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        // Aggregate each ingredient across meals; amounts add up when the
        // units agree.
        var order: [String] = []
        var needs: [String: (name: String, quantity: Double?, unit: QuantityUnit?, meals: [PlannedMeal])] = [:]
        var leftOff = Set<String>()
        for meal in meals {
            for item in meal.items {
                let key = Self.key(for: item.name)
                guard !key.isEmpty else { continue }
                if PantryMatch.item(for: item.name, in: pantry) != nil {
                    leftOff.insert(key)
                    continue
                }
                if var need = needs[key] {
                    if need.unit == item.unit, let a = need.quantity, let b = item.quantity {
                        need.quantity = a + b
                    } else if need.quantity == nil {
                        need.quantity = item.quantity
                        need.unit = item.unit
                    }
                    if !need.meals.contains(where: { $0.id == meal.id }) { need.meals.append(meal) }
                    needs[key] = need
                } else {
                    order.append(key)
                    needs[key] = (item.name, item.quantity, item.unit, [meal])
                }
            }
        }

        var lines: [Line] = order.compactMap { key in
            guard let need = needs[key] else { return nil }
            let state = statesByKey[key].flatMap { $0.isManual ? nil : $0 }
            if state?.isDismissed == true { return nil }
            let override = state?.quantity
            return Line(
                key: key, name: need.name,
                quantity: override ?? need.quantity, unit: override != nil ? state?.unit : need.unit,
                aisle: state?.aisle ?? GroceryAisle.guess(for: need.name),
                isChecked: state?.isChecked ?? false, isManual: false, meals: need.meals, state: state
            )
        }
        for item in current where item.isManual && !item.isDismissed && needs[item.key] == nil {
            lines.append(Line(
                key: item.key, name: item.name, quantity: item.quantity, unit: item.unit,
                aisle: item.aisle ?? GroceryAisle.guess(for: item.name),
                isChecked: item.isChecked, isManual: true, meals: [], state: item
            ))
        }

        let aisleOrder = Dictionary(uniqueKeysWithValues: GroceryAisle.allCases.enumerated().map { ($1, $0) })
        self.lines = lines.sorted { lhs, rhs in
            if lhs.isChecked != rhs.isChecked { return !lhs.isChecked }
            if lhs.aisle != rhs.aisle { return aisleOrder[lhs.aisle, default: 0] < aisleOrder[rhs.aisle, default: 0] }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        self.leftOffCount = leftOff.count
        self.plannedMealCount = meals.count
    }

    /// Done shopping: the pantry items for the checked lines. Fresh aisles
    /// go to the fridge, the rest to the cupboard; no use-by date is
    /// guessed.
    func pantryItems(now: Date) -> [InventoryItem] {
        checked.map { line in
            InventoryItem(
                id: UUID(), name: line.name,
                quantity: line.quantity ?? 1, unit: line.quantity == nil ? .piece : (line.unit ?? .piece),
                purchaseDate: now, expirationDate: nil, category: .other,
                location: [.produce, .fish, .dairyEggs].contains(line.aisle) ? .fridge : .pantry,
                notes: nil, status: .available, reminderSnoozedUntil: nil
            )
        }
    }
}
