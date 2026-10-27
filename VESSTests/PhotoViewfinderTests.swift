import CoreGraphics
import Testing
@testable import VESS

@Suite("Photo viewfinder")
@MainActor
struct PhotoViewfinderTests {
    @Test("Always the full content width; 3:4 when there's room, else as tall as fits above the shutter")
    func size() {
        let tall = AddPhotoContent.viewfinderSize(in: CGSize(width: 402, height: 700))
        #expect(tall.width == 362 && abs(tall.height - 362 * 4 / 3) < 0.01)
        let short = AddPhotoContent.viewfinderSize(in: CGSize(width: 375, height: 520))
        #expect(short.width == 335 && short.height == 520 - 84 - 48)
    }
}
