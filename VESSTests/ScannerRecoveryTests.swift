import Testing
@testable import VESS

@Suite("Scanner recovery")
struct ScannerRecoveryTests {
    @Test("A running scanner with a running session is left alone, even right after the torch goes off")
    func leaveAlone() {
        #expect(ScannerRecovery.action(isScanning: true, sessionRunning: true) == .none)
        #expect(ScannerRecovery.action(isScanning: true, sessionRunning: nil) == .none)
    }

    @Test("A scanner that stopped is started; one whose session stopped underneath is restarted")
    func recover() {
        #expect(ScannerRecovery.action(isScanning: false, sessionRunning: nil) == .start)
        #expect(ScannerRecovery.action(isScanning: false, sessionRunning: false) == .start)
        #expect(ScannerRecovery.action(isScanning: true, sessionRunning: false) == .restart)
        #expect(ScannerRecovery.restartPause > .zero)
    }
}
