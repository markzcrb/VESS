import AVFoundation
import OSLog
import SwiftUI
import VisionKit

/// Owns the barcode scanner's torch and keeps the live scanner running.
///
/// What stopped the camera after the torch went off (device bug, Oct 2026):
/// - Before the scanner's session reported it was running, the torch was
///   set on `AVCaptureDevice.default(for: .video)`: on Pro iPhones that's the
///   wide camera, while VisionKit runs a multi-camera device, so the running
///   session was reconfigured under it.
/// - `unlockForConfiguration()` was also called when the lock had failed.
/// - Every "torch off" forced `stopScanning()` and an immediate
///   `startScanning()`, even when the feed was still running, and "running"
///   was read from any capture session in the app. A synchronous stop/start
///   can leave VisionKit's preview frozen.
///
/// Now:
/// - The torch is only offered and set on the camera of the scanner's own
///   session, once that session runs; the lock is balanced.
/// - Only that session's notifications count, and its `isRunning` is read
///   directly.
/// - After the torch goes off (by VESS, heat, or the system), the scanner
///   is left alone if its session still runs; otherwise it's stopped, and
///   started again a moment later (`ScannerRecovery`).
///
/// Every step is logged (subsystem "VESS", category "Scanner").
@Observable
final class ScannerController {
    private(set) var isTorchOn = false
    private(set) var isTorchAvailable = false
    private(set) var hasTorch = false

    @ObservationIgnored private weak var scanner: DataScannerViewController?
    @ObservationIgnored private weak var session: AVCaptureSession?
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var torchObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var recovery: Task<Void, Never>?

    private static let logger = Logger(subsystem: "VESS", category: "Scanner")

    init() {
        observeSessions()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Scanner lifecycle

    func attach(_ scanner: DataScannerViewController) {
        self.scanner = scanner
        recover(reason: "attach", after: .zero)
    }

    func detach() {
        Self.logger.info("scanner: detach")
        recovery?.cancel()
        scanner?.stopScanning()
        scanner = nil
        session = nil
    }

    /// VisionKit reported the scanner unavailable (for example the camera
    /// was taken by another app). Try again once it can scan.
    func scannerBecameUnavailable(_ error: DataScannerViewController.ScanningUnavailable) {
        Self.logger.error("scanner: became unavailable \(String(describing: error), privacy: .public)")
        recover(reason: "unavailable", after: .seconds(1))
    }

    // MARK: Torch

    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else {
            Self.logger.info("torch: no camera yet")
            return
        }
        guard !on || device.isTorchAvailable else {
            Self.logger.info("torch: unavailable, not turning on")
            refreshTorch()
            return
        }
        do {
            try device.lockForConfiguration()
        } catch {
            Self.logger.error("torch: lock failed \(error.localizedDescription, privacy: .public)")
            refreshTorch()
            return
        }
        defer { device.unlockForConfiguration() }
        do {
            if on {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else if device.torchMode != .off {
                device.torchMode = .off
            }
            Self.logger.info("torch: set \(on, privacy: .public) on \(Self.describe(device), privacy: .public)")
        } catch {
            Self.logger.error("torch: failed \(error.localizedDescription, privacy: .public)")
        }
        refreshTorch()
    }

    private func refreshTorch() {
        guard let device else {
            hasTorch = false
            isTorchAvailable = false
            isTorchOn = false
            return
        }
        let wasOn = isTorchOn
        hasTorch = device.hasTorch
        isTorchAvailable = device.hasTorch && device.isTorchAvailable
        isTorchOn = device.isTorchActive
        // Off, by VESS or the system (heat, Control Center): check the feed.
        if wasOn && !isTorchOn {
            recover(reason: "torch went off", after: .milliseconds(500))
        }
    }

    /// Uses the scanner session's camera for the torch and follows its state.
    private func adopt(_ device: AVCaptureDevice) {
        guard device.uniqueID != self.device?.uniqueID else { return }
        Self.logger.info("torch: using \(Self.describe(device), privacy: .public)")
        self.device = device
        torchObservations = [
            // KVO calls back on any thread; the state is updated on the main actor.
            device.observe(\.isTorchActive, options: [.new]) { [weak self] _, _ in
                let controller = self
                Task { @MainActor in controller?.refreshTorch() }
            },
            device.observe(\.isTorchAvailable, options: [.new]) { [weak self] _, _ in
                let controller = self
                Task { @MainActor in controller?.refreshTorch() }
            },
        ]
        refreshTorch()
    }

    // MARK: Keeping the scanner running

    private func observeSessions() {
        let names: [Notification.Name] = [
            AVCaptureSession.didStartRunningNotification,
            AVCaptureSession.didStopRunningNotification,
            AVCaptureSession.wasInterruptedNotification,
            AVCaptureSession.interruptionEndedNotification,
            AVCaptureSession.runtimeErrorNotification,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let session = note.object as? AVCaptureSession
                let camera = session?.inputs.lazy.compactMap { ($0 as? AVCaptureDeviceInput)?.device }.first { $0.hasMediaType(.video) }
                let reason = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
                let error = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError).map { "\($0.domain) \($0.code)" }
                let name = note.name
                MainActor.assumeIsolated {
                    self?.sessionChanged(name, session: session, camera: camera, interruptionReason: reason, error: error)
                }
            })
        }
    }

    private func sessionChanged(_ name: Notification.Name, session: AVCaptureSession?, camera: AVCaptureDevice?, interruptionReason: Int?, error: String?) {
        // The scanner's session is the one that starts while it's attached;
        // other capture sessions in the app are ignored.
        if name == AVCaptureSession.didStartRunningNotification, scanner != nil, self.session == nil {
            self.session = session
        }
        guard let session, session === self.session else { return }
        Self.logger.info("session: \(name.rawValue, privacy: .public) camera=\(camera.map(Self.describe) ?? "-", privacy: .public) reason=\(interruptionReason.map(String.init) ?? "-", privacy: .public) error=\(error ?? "-", privacy: .public)")
        switch name {
        case AVCaptureSession.didStartRunningNotification:
            if let camera { adopt(camera) }
        case AVCaptureSession.didStopRunningNotification, AVCaptureSession.runtimeErrorNotification:
            recover(reason: "session stopped", after: .milliseconds(500))
        case AVCaptureSession.interruptionEndedNotification:
            recover(reason: "interruption ended", after: .milliseconds(500))
        default:
            break
        }
        refreshTorch()
    }

    /// After `delay`, does what `ScannerRecovery` says for the current state.
    private func recover(reason: String, after delay: Duration) {
        recovery?.cancel()
        recovery = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let scanner = self.scanner, DataScannerViewController.isAvailable else { return }
            let action = ScannerRecovery.action(isScanning: scanner.isScanning, sessionRunning: self.session?.isRunning)
            Self.logger.info("scanner: \(reason, privacy: .public) isScanning=\(scanner.isScanning, privacy: .public) session=\(self.session.map { $0.isRunning ? "running" : "stopped" } ?? "unknown", privacy: .public) -> \(String(describing: action), privacy: .public)")
            switch action {
            case .none:
                return
            case .start:
                self.start(scanner)
            case .restart:
                scanner.stopScanning()
                // Not in the same turn: a synchronous stop/start can freeze the preview.
                try? await Task.sleep(for: ScannerRecovery.restartPause)
                guard !Task.isCancelled, self.scanner === scanner else { return }
                self.start(scanner)
            }
        }
    }

    private func start(_ scanner: DataScannerViewController) {
        do {
            try scanner.startScanning()
        } catch {
            Self.logger.error("scanner: start failed \(String(describing: error), privacy: .public)")
        }
    }

    nonisolated private static func describe(_ device: AVCaptureDevice) -> String {
        "\(device.deviceType.rawValue) torch=\(device.isTorchActive) available=\(device.isTorchAvailable)"
    }
}

/// What to do with the scanner after something may have stopped it.
/// Pure, so the rule is tested without a camera.
nonisolated enum ScannerRecovery: Equatable, Sendable {
    case none, start, restart

    /// The pause between stopping and starting again.
    static let restartPause: Duration = .milliseconds(300)

    /// - Parameters:
    ///   - isScanning: what the scanner says.
    ///   - sessionRunning: the scanner's own session, `nil` before it's known.
    static func action(isScanning: Bool, sessionRunning: Bool?) -> ScannerRecovery {
        switch (isScanning, sessionRunning) {
        case (false, _): .start
        case (true, false?): .restart
        case (true, true?), (true, nil): .none
        }
    }
}
