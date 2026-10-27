import CoreGraphics
import Testing
@testable import VESS

@Suite("Photo viewfinder")
@MainActor
struct PhotoViewfinderTests {
    @Test("Full content width at 3:4 when there's room; smaller but still 3:4 above the shutter on a short screen")
    func size() {
        let tall = AddPhotoContent.viewfinderSize(in: CGSize(width: 402, height: 700))
        #expect(tall.width == 362 && abs(tall.height - 362 * 4 / 3) < 0.01)
        let short = AddPhotoContent.viewfinderSize(in: CGSize(width: 375, height: 520))
        #expect(short.height == 520 - 84 - 48 && abs(short.width - short.height * 3 / 4) < 0.01)
    }
}
