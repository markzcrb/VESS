import AVFoundation
import OSLog
import SwiftUI
import VisionKit

/// Owns the barcode scanner's torch and keeps the live scanner running.
///
/// - The torch is switched on the camera the scanner's own capture session
///   uses (read from the session when it starts), not on whatever
///   `AVCaptureDevice.default(for:)` returns.
/// - `isTorchOn` and `isTorchAvailable` come from the hardware (KVO), so the
///   button follows the real torch, including when the system turns it off
///   (heat, Control Center, a session restart).
/// - Whenever the session stops, is interrupted or fails, or the torch goes
///   off, scanning is checked and restarted if it isn't running.
///
/// Every step is logged (subsystem "VESS", category "Scanner") so a device
/// test shows which case happened.
@Observable
final class ScannerController {
    private(set) var isTorchOn = false
    private(set) var isTorchAvailable = false
    private(set) var hasTorch = false

    @ObservationIgnored private weak var scanner: DataScannerViewController?
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var isSessionRunning = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var torchObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var restart: Task<Void, Never>?

    private static let logger = Logger(subsystem: "VESS", category: "Scanner")

    init() {
        observeSessions()
        if let device = AVCaptureDevice.default(for: .video) { adopt(device) }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: Scanner lifecycle

    func attach(_ scanner: DataScannerViewController) {
        self.scanner = scanner
        ensureScanning(reason: "attach")
    }

    func detach() {
        Self.logger.info("scanner: detach")
        restart?.cancel()
        scanner?.stopScanning()
        scanner = nil
    }

    /// VisionKit reported the scanner unavailable (for example the camera
    /// was taken by another app). Try again once it can scan.
    func scannerBecameUnavailable(_ error: DataScannerViewController.ScanningUnavailable) {
        Self.logger.error("scanner: became unavailable \(String(describing: error), privacy: .public)")
        scheduleRestart(reason: "unavailable", after: .seconds(1))
    }

    // MARK: Torch

    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else {
            Self.logger.info("torch: no torch")
            return
        }
        guard !on || device.isTorchAvailable else {
            Self.logger.info("torch: unavailable, not turning on")
            refreshTorch()
            return
        }
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            Self.logger.info("torch: set \(on, privacy: .public) on \(Self.describe(device), privacy: .public)")
        } catch {
            device.unlockForConfiguration()
            Self.logger.error("torch: failed \(error.localizedDescription, privacy: .public)")
        }
        refreshTorch()
        if !on { scheduleRestart(reason: "torch off", after: .milliseconds(300)) }
    }

    private func refreshTorch() {
        guard let device else { return }
        let wasOn = isTorchOn
        hasTorch = device.hasTorch
        isTorchAvailable = device.hasTorch && device.isTorchAvailable
        isTorchOn = device.isTorchActive
        // Turned off by something other than VESS: make sure scanning survived.
        if wasOn && !isTorchOn {
            scheduleRestart(reason: "torch went off", after: .milliseconds(300))
        }
    }

    /// Uses this camera for the torch and follows its torch state.
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
                    self?.sessionChanged(name, camera: camera, interruptionReason: reason, error: error)
                }
            })
        }
    }

    private func sessionChanged(_ name: Notification.Name, camera: AVCaptureDevice?, interruptionReason: Int?, error: String?) {
        Self.logger.info("session: \(name.rawValue, privacy: .public) camera=\(camera.map(Self.describe) ?? "-", privacy: .public) reason=\(interruptionReason.map(String.init) ?? "-", privacy: .public) error=\(error ?? "-", privacy: .public)")
        switch name {
        case AVCaptureSession.didStartRunningNotification:
            isSessionRunning = true
            if let camera, camera.hasTorch { adopt(camera) }
        case AVCaptureSession.didStopRunningNotification, AVCaptureSession.runtimeErrorNotification:
            isSessionRunning = false
            scheduleRestart(reason: "session stopped", after: .milliseconds(400))
        case AVCaptureSession.interruptionEndedNotification:
            scheduleRestart(reason: "interruption ended", after: .milliseconds(400))
        default:
            break
        }
        refreshTorch()
    }

    private func scheduleRestart(reason: String, after delay: Duration) {
        restart?.cancel()
        restart = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.ensureScanning(reason: reason)
        }
    }

    /// Starts scanning if it isn't running. A scanner that says it's scanning
    /// while its session has stopped is restarted.
    private func ensureScanning(reason: String) {
        guard let scanner, DataScannerViewController.isAvailable else { return }
        if scanner.isScanning && isSessionRunning { return }
        Self.logger.info("scanner: restart (\(reason, privacy: .public)) isScanning=\(scanner.isScanning, privacy: .public) sessionRunning=\(self.isSessionRunning, privacy: .public)")
        if scanner.isScanning { scanner.stopScanning() }
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
