import AVFoundation
import OSLog
import SwiftUI
import UIKit

/// The photo camera for estimates (I02). Its own capture session, run on
/// one serial queue, following the scanner's rules: the session is only
/// configured before it runs (flash is a per-photo setting, never a device
/// reconfiguration), it's never stopped and started synchronously, and
/// after an interruption or error it starts again a moment later if it
/// isn't running. Logged as subsystem "VESS", category "PhotoCamera".
@Observable
final class PhotoCameraController {
    enum State: Equatable { case idle, running, unavailable, denied }

    private(set) var state: State = .idle
    private(set) var hasFlash = false
    var isFlashOn = false

    @ObservationIgnored let box = CaptureBox()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let logger = Logger(subsystem: "VESS", category: "PhotoCamera")

    init() {
        let names: [Notification.Name] = [AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: box.session, queue: .main) { [box] note in
                Self.logger.info("session: \(note.name.rawValue, privacy: .public); starting again if stopped")
                box.startIfNeeded(after: 0.5)
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { state = .denied; return }
        case .denied, .restricted:
            state = .denied
            return
        default:
            break
        }
        let result = await box.configureAndStart()
        hasFlash = result.hasFlash
        state = result.ok ? .running : .unavailable
        Self.logger.info("start: \(String(describing: self.state), privacy: .public) flash=\(result.hasFlash, privacy: .public)")
    }

    func stop() {
        box.stop()
        if state == .running { state = .idle }
    }

    /// The photo's data (HEIC or JPEG), or `nil` if it failed.
    func capture() async -> Data? {
        await box.capture(flash: isFlashOn && hasFlash)
    }
}

/// Owns the session and its queue. Everything runs on `queue`.
nonisolated final class CaptureBox: @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "VESS.photoCamera")
    private var isConfigured = false
    private var delegates: [Int64: PhotoDelegate] = [:]

    func configureAndStart() async -> (ok: Bool, hasFlash: Bool) {
        await withCheckedContinuation { continuation in
            queue.async {
                if !self.isConfigured {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let input = try? AVCaptureDeviceInput(device: device),
                          self.session.canAddInput(input), self.session.canAddOutput(self.output)
                    else {
                        continuation.resume(returning: (false, false))
                        return
                    }
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    self.session.addInput(input)
                    self.session.addOutput(self.output)
                    self.session.commitConfiguration()
                    self.isConfigured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
                let hasFlash = self.output.supportedFlashModes.contains(.on)
                continuation.resume(returning: (self.session.isRunning, hasFlash))
            }
        }
    }

    func startIfNeeded(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) {
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func capture(flash: Bool) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.session.isRunning else {
                    continuation.resume(returning: nil)
                    return
                }
                let settings = AVCapturePhotoSettings()
                if flash, self.output.supportedFlashModes.contains(.on) { settings.flashMode = .on }
                let id = settings.uniqueID
                let delegate = PhotoDelegate { data in
                    self.queue.async { self.delegates[id] = nil }
                    continuation.resume(returning: data)
                }
                self.delegates[id] = delegate
                self.output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

nonisolated private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Data?) -> Void
    private var finished = false

    init(completion: @escaping (Data?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard !finished else { return }
        finished = true
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

/// The live preview.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
