import SwiftUI
import UIKit

extension RecipeCategory {
    var title: LocalizedStringResource {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        case .smoothie: "Smoothie"
        case .dessert: "Dessert"
        }
    }
}

extension RecipeDiscover.MealFilter {
    var title: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks"
        case .smoothies: "Smoothies"
        case .desserts: "Desserts"
        }
    }
}

extension RecipeDiscover.Collection {
    var title: LocalizedStringResource {
        switch self {
        case .vegan: "Vegan"
        case .vegetarian: "Vegetarian"
        case .fishAndSeafood: "Fish and seafood"
        case .glutenFree: "Gluten-free"
        case .dairyFree: "Dairy-free"
        case .highProtein: "High-protein"
        case .under20Minutes: "Under 20 min"
        }
    }

    /// The dot on the tile: the metric hue it relates to, else greyscale.
    var color: Color {
        switch self {
        case .highProtein: VESSColor.protein
        case .vegan, .vegetarian: VESSColor.statusOptimal
        case .glutenFree, .dairyFree: VESSColor.carbs
        case .fishAndSeafood: VESSColor.water
        case .under20Minutes: VESSColor.secondaryText
        }
    }
}

extension Recipe {
    /// "Vegan", "Vegetarian", "Pescatarian", or nothing.
    var dietLabel: LocalizedStringResource? {
        if dietTags.contains(.vegan) { return "Vegan" }
        if dietTags.contains(.vegetarian) { return "Vegetarian" }
        if dietTags.contains(.pescatarian) || diets == [.pescatarian] { return "Pescatarian" }
        return nil
    }

    /// "BREAKFAST · VEGETARIAN", "DINNER · YOUR RECIPE", "LUNCH · FROM AI CHEF".
    var kicker: Text {
        let second: LocalizedStringResource? = switch origin {
        case .discover: dietLabel
        case .user: "Your recipe"
        case .ai: "From AI Chef"
        }
        guard let second else { return Text(category.title) }
        return Text("\(Text(category.title)) · \(Text(second))")
    }

    /// "25 min · 620 kcal · 42 g protein".
    var metaLine: Text {
        Text("\(minutes) min · \(VESSFormat.calories(nutrition.calories)) kcal · \(VESSFormat.grams(nutrition.proteinGrams)) g protein")
    }

    /// The bundled photo, or the user's own; `nil` for the quiet tile.
    @MainActor
    func photoImage(store: LocalStore) -> Image? {
        if origin == .discover, let photo, let image = UIImage(named: photo) {
            return Image(uiImage: image)
        }
        if origin != .discover, let data = store.recipePhoto(id: id), let image = UIImage(data: data) {
            return Image(uiImage: image)
        }
        return nil
    }
}

extension RecipeFit.Reason {
    /// "Has chicken", "Contains mushrooms", "Not vegan", "Meat with dairy".
    var text: Text {
        switch self {
        case .has(let content, let ingredient):
            if let ingredient { return Text("Has \(ingredient)") }
            return Text("Has \(Text(content.title))")
        case .notTagged(let diet): return Text("Not \(String(localized: diet.title).lowercased())")
        case .meatWithDairy: return Text("Meat with dairy")
        case .avoid(let item): return Text("Contains \(item.lowercased())")
        }
    }
}

extension Recipe.Content {
    var title: LocalizedStringResource {
        switch self {
        case .meat: "meat"
        case .poultry: "poultry"
        case .pork: "pork"
        case .fish: "fish"
        case .shellfish: "shellfish"
        case .molluscs: "molluscs"
        case .dairy: "dairy"
        case .egg: "egg"
        case .alcohol: "alcohol"
        }
    }
}

extension Allergen {
    /// "nuts", "peanuts", "milk": inside a sentence.
    var shortTitle: LocalizedStringResource {
        switch self {
        case .gluten: "gluten"
        case .crustaceans: "shellfish"
        case .eggs: "eggs"
        case .fish: "fish"
        case .peanuts: "peanuts"
        case .soy: "soy"
        case .milk: "milk"
        case .nuts: "nuts"
        case .celery: "celery"
        case .mustard: "mustard"
        case .sesame: "sesame"
        case .sulphites: "sulphites"
        case .lupin: "lupin"
        case .molluscs: "molluscs"
        }
    }
}

extension RecipeDiscover.HiddenGroup {
    /// What hidden recipes contain: "meat", "nuts", "coriander".
    var noun: String? {
        switch self {
        case .allergen(let allergen): String(localized: allergen.shortTitle)
        case .meat: String(localized: "meat")
        case .content(let content): String(localized: content.title)
        case .avoid(let item): item.lowercased()
        case .notTagged, .meatWithDairy: nil
        }
    }

    /// "9 have nuts", "1 isn't vegan".
    func countText(_ count: Int) -> String {
        switch self {
        case .notTagged(let diet): String(localized: "\(count) aren't \(String(localized: diet.title).lowercased())")
        case .meatWithDairy: String(localized: "\(count) have meat with dairy")
        default: count == 1 ? String(localized: "1 has \(noun ?? "")") : String(localized: "\(count) have \(noun ?? "")")
        }
    }
}

enum RecipeText {
    /// "Fits you: Pescatarian · no nuts · no coriander".
    static func fitsYou(_ profile: UserProfile) -> String {
        var parts: [String] = []
        let preferences = profile.preferences
        if preferences.diet != .noRestrictions { parts.append(String(localized: preferences.diet.title)) }
        // Peanuts and tree nuts read as one "no nuts".
        var allergies = Allergen.allCases.filter { profile.allergies.contains($0) }
        if allergies.contains(.nuts) && allergies.contains(.peanuts) { allergies.removeAll { $0 == .peanuts } }
        parts += allergies.map { String(localized: "no \(String(localized: $0.shortTitle))") }
        parts += preferences.avoidIngredients.map { String(localized: "no \($0.lowercased())") }
        guard !parts.isEmpty else { return String(localized: "Fits you: everything") }
        return String(localized: "Fits you: \(parts.joined(separator: " · "))")
    }

    /// "31 recipes are hidden because they contain meat, nuts, peanuts or mushrooms."
    static func hidden(_ summary: RecipeDiscover.HiddenSummary) -> String {
        let nouns = summary.groups.compactMap(\.group.noun)
        if nouns.count == summary.groups.count, !nouns.isEmpty {
            let list = nouns.formatted(.list(type: .or))
            return summary.total == 1
                ? String(localized: "1 recipe is hidden because it contains \(list).")
                : String(localized: "\(summary.total) recipes are hidden because they contain \(list).")
        }
        return summary.total == 1
            ? String(localized: "1 recipe is hidden because it doesn't fit your preferences.")
            : String(localized: "\(summary.total) recipes are hidden because they don't fit your preferences.")
    }

    /// "21 have meat · 5 have nuts · 4 have peanuts".
    static func why(_ summary: RecipeDiscover.HiddenSummary) -> String {
        // Each count stays on one line ("1 has mushrooms").
        summary.groups.map { $0.group.countText($0.count).replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")
    }

    /// "use by Thu", "use today"; one phrase that never breaks.
    static func useBy(_ item: InventoryItem, now: Date, calendar: Calendar) -> String {
        let text = switch item.expirationStatus(now: now, calendar: calendar) {
        case .today: String(localized: "use today")
        default:
            item.expirationDate.map { String(localized: "use by \($0.formatted(.dateTime.weekday(.abbreviated)))") } ?? String(localized: "use soon")
        }
        return text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// The card's badges: what it uses that expires soon, or how much is at
    /// home; what it leaves out; why it doesn't fit.
    static func badges(for recipe: Recipe, fit: RecipeFit, pantry: [InventoryItem], now: Date, calendar: Calendar) -> [VESSRecipeBadge] {
        var badges: [VESSRecipeBadge] = []
        let use = AIChef.pantryUse(recipe, pantry: pantry, now: now, calendar: calendar)
        if let first = use.useSoon.first {
            badges.append(.init(text: Text("Uses \(first.name.lowercased()) · \(useBy(first, now: now, calendar: calendar))"), tone: .accent))
        } else if use.atHomeCount > 0 {
            let all = use.atHomeCount == use.countedTotal
            badges.append(.init(text: Text("\(use.atHomeCount) of \(use.countedTotal) at home"), tone: all ? .positive : .neutral))
        }
        for item in fit.skipped {
            badges.append(.init(text: Text("Without \(item.lowercased())")))
        }
        for reason in fit.reasons {
            badges.append(.init(text: reason.text, tone: .warning))
        }
        return badges
    }
}
