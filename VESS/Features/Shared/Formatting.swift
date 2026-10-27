import Foundation

/// Number formats used across screens, so the same value always reads the same way.
///
/// Numbers never wrap: thousands are grouped with a narrow no-break space
/// (U+202F, "1 040") whatever the locale's grouping; the decimal mark
/// stays the locale's. Between a number and its unit, copy uses a no-break
/// space (U+00A0, "250 ml"); `unitSpace` names it.
enum VESSFormat {
    /// Between a number and its unit: "250 ml", "1 h 08".
    static let unitSpace = "\u{00A0}"
    /// Groups thousands: "1 040".
    static let groupSpace = "\u{202F}"

    /// The one number format: locale decimals, U+202F between thousands.
    static func number(_ value: Double, fractionLength: ClosedRange<Int>) -> String {
        groupThousands(value.formatted(.number.precision(.fractionLength(fractionLength)).grouping(.never)))
    }

    /// "1040" → "1 040", "-12345,6" → "-12 345,6": U+202F every three
    /// digits of the whole part. The locale's own grouping isn't used: the
    /// region can make it a breaking or a different space.
    static func groupThousands(_ text: String) -> String {
        guard let start = text.firstIndex(where: \.isNumber) else { return text }
        let end = text[start...].firstIndex(where: { !$0.isNumber }) ?? text.endIndex
        let digits = Array(text[start..<end])
        guard digits.count > 3 else { return text }
        var grouped = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { grouped += groupSpace }
            grouped.append(digit)
        }
        return String(text[..<start]) + grouped + String(text[end...])
    }

    /// Whole kilocalories: "1 840".
    static func calories(_ value: Double) -> String {
        number(value, fractionLength: 0...0)
    }

    /// Whole grams: "108".
    static func grams(_ value: Double) -> String {
        number(value, fractionLength: 0...0)
    }

    /// Liters with one decimal: "1.4". Nothing reads as "0", not "0.0".
    static func liters(fromMilliliters value: Double) -> String {
        guard value > 0 else { return 0.formatted() }
        return number(value / 1000, fractionLength: 1...1)
    }

    /// Whole milliliters: "240".
    static func milliliters(_ value: Double) -> String {
        number(value, fractionLength: 0...0)
    }

    /// Short quantities: "150", "1.5".
    static func quantity(_ value: Double) -> String {
        number(value, fractionLength: 0...1)
    }

    /// "7 h 12", "1 h 08", "22 min", never split across lines.
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        guard total >= 60 else { return "\(total)\(unitSpace)" + String(localized: "min") }
        let minutesPart = (total % 60).formatted(.number.precision(.integerLength(2)))
        return "\(total / 60)\(unitSpace)h\(unitSpace)\(minutesPart)"
    }

    /// Parses user-typed numbers, accepting either decimal separator.
    static func number(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}

extension VESSFormat {
    /// Whole steps: "6 420".
    static func steps(_ value: Double) -> String {
        number(value, fractionLength: 0...0)
    }

    /// Kilometers with one decimal: "5.2".
    static func kilometers(fromMeters value: Double) -> String {
        number(value / 1000, fractionLength: 1...1)
    }
}
