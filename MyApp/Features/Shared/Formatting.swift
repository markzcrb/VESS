import Foundation

/// Number formats used across screens, so the same value always reads the same way.
enum VESSFormat {
    /// Whole kilocalories: "1,840".
    static func calories(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Whole grams: "108".
    static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Liters with one decimal: "1.4". Nothing reads as "0", not "0.0".
    static func liters(fromMilliliters value: Double) -> String {
        guard value > 0 else { return 0.formatted() }
        return (value / 1000).formatted(.number.precision(.fractionLength(1)))
    }

    /// Whole milliliters: "240".
    static func milliliters(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Short quantities: "150", "1.5".
    static func quantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Parses user-typed numbers, accepting either decimal separator.
    static func number(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}
