import Foundation
import Testing
@testable import VESS

@Suite("Photo camera keep-alive")
struct CameraKeepAliveTests {
    private let closed = Date(timeIntervalSince1970: 1_000)

    @Test("A closed camera is taken apart only after 30 s unused")
    func tearsDownAfter30s() {
        var keepAlive = CameraKeepAlive()
        keepAlive.acquire()
        let token = keepAlive.release(at: closed)
        #expect(!keepAlive.shouldTearDown(token: token, now: closed.addingTimeInterval(29.9)))
        #expect(keepAlive.shouldTearDown(token: token, now: closed.addingTimeInterval(30)))
    }

    @Test("Reopening within 30 s keeps it; the old teardown never runs")
    func reopenKeeps() {
        var keepAlive = CameraKeepAlive()
        keepAlive.acquire()
        let first = keepAlive.release(at: closed)
        keepAlive.acquire()
        #expect(!keepAlive.shouldTearDown(token: first, now: closed.addingTimeInterval(60)), "In use again")
        let second = keepAlive.release(at: closed.addingTimeInterval(10))
        #expect(!keepAlive.shouldTearDown(token: first, now: closed.addingTimeInterval(60)), "Only the latest release counts")
        #expect(keepAlive.shouldTearDown(token: second, now: closed.addingTimeInterval(40)))
    }

    @Test("Nothing is torn down while the camera is in use")
    func inUse() {
        var keepAlive = CameraKeepAlive()
        keepAlive.acquire()
        #expect(keepAlive.isInUse)
        #expect(!keepAlive.shouldTearDown(token: keepAlive.generation, now: closed.addingTimeInterval(1_000)))
    }
}
