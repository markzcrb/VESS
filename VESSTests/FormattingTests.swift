import Foundation
import Testing
@testable import VESS

@Suite("Numbers and units never wrap")
struct FormattingTests {
    @Test("Thousands are grouped with U+202F; decimals keep the locale's mark")
    func grouping() {
        #expect(VESSFormat.groupThousands("1040") == "1\u{202F}040")
        #expect(VESSFormat.groupThousands("-12345,6") == "-12\u{202F}345,6")
        #expect(VESSFormat.groupThousands("1234567.25") == "1\u{202F}234\u{202F}567.25")
        #expect(VESSFormat.groupThousands("840") == "840")
        #expect(VESSFormat.calories(1040) == "1\u{202F}040")
        #expect(VESSFormat.steps(6420) == "6\u{202F}420")
    }

    @Test("Durations: \"1 h 08\" and \"22 min\" with no-break spaces")
    func duration() {
        #expect(VESSFormat.duration(minutes: 68) == "1\u{00A0}h\u{00A0}08")
        #expect(VESSFormat.duration(minutes: 22) == "22\u{00A0}min")
        #expect(HealthFormat.duration(minutes: 432) == "7\u{00A0}h\u{00A0}12")
    }
}
