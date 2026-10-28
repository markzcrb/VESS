import AVFoundation
import OSLog
import SwiftUI
import UIKit
import Vision

/// The camera for Photo (I02, M01): photos for estimates, and barcodes read
/// from the same live session (metadata output), so switching between Meal,
/// Menu and Barcode never restarts the camera. Its own capture session, run on
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
    private(set) var hasTorch = false
    private(set) var isTorchOn = false

    /// A barcode seen while `detectsBarcodes` is on. Detection pauses after
    /// each code until it's turned on again.
    @ObservationIgnored var onBarcode: ((String) -> Void)?
    var detectsBarcodes = false {
        didSet { box.setDetecting(detectsBarcodes) }
    }

    @ObservationIgnored let box = CaptureBox()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private static let logger = Logger(subsystem: AppLog.subsystem, category: "PhotoCamera")

    init() {
        box.onCode = { [weak self] code in
            Task { @MainActor in
                guard let self, self.detectsBarcodes else { return }
                self.detectsBarcodes = false
                self.onBarcode?(code)
            }
        }
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
        hasTorch = result.hasTorch
        box.setDetecting(detectsBarcodes)
        state = result.ok ? .running : .unavailable
        Self.logger.info("start: \(String(describing: self.state), privacy: .public) flash=\(result.hasFlash, privacy: .public)")
    }

    func stop() {
        setTorch(false)
        box.stop()
        if state == .running { state = .idle }
    }

    /// The light for scanning barcodes (Barcode mode's bolt).
    func setTorch(_ on: Bool) {
        guard hasTorch || !on else { return }
        isTorchOn = on
        box.setTorch(on)
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
    private let metadata = AVCaptureMetadataOutput()
    private let metadataDelegate = MetadataDelegate()
    private let queue = DispatchQueue(label: "VESS.photoCamera")
    private var isConfigured = false
    private var device: AVCaptureDevice?
    private var delegates: [Int64: PhotoDelegate] = [:]
    /// Called on the camera's queue with each product barcode while detecting.
    var onCode: ((String) -> Void)? {
        get { metadataDelegate.onCode }
        set { metadataDelegate.onCode = newValue }
    }

    /// Product barcodes, as the scanner reads them.
    static let barcodeTypes: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128]

    func configureAndStart() async -> (ok: Bool, hasFlash: Bool, hasTorch: Bool) {
        await withCheckedContinuation { continuation in
            queue.async {
                if !self.isConfigured {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                          let input = try? AVCaptureDeviceInput(device: device),
                          self.session.canAddInput(input), self.session.canAddOutput(self.output)
                    else {
                        continuation.resume(returning: (false, false, false))
                        return
                    }
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    self.session.addInput(input)
                    self.session.addOutput(self.output)
                    // Barcodes come from the same session; detection is
                    // switched on and off by `setDetecting`, never by
                    // reconfiguring a running session.
                    if self.session.canAddOutput(self.metadata) {
                        self.session.addOutput(self.metadata)
                        self.metadata.setMetadataObjectsDelegate(self.metadataDelegate, queue: self.queue)
                        self.metadata.metadataObjectTypes = Self.barcodeTypes.filter(self.metadata.availableMetadataObjectTypes.contains)
                    }
                    self.session.commitConfiguration()
                    self.device = device
                    self.isConfigured = true
                }
                if !self.session.isRunning { self.session.startRunning() }
                let hasFlash = self.output.supportedFlashModes.contains(.on)
                continuation.resume(returning: (self.session.isRunning, hasFlash, self.device?.hasTorch == true))
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

    func setDetecting(_ on: Bool) {
        queue.async { self.metadataDelegate.isOn = on }
    }

    /// Torch on or off; skipped while the system holds it back (heat).
    func setTorch(_ on: Bool) {
        queue.async {
            guard let device = self.device, device.hasTorch, device.isTorchAvailable || !on,
                  (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
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

/// Forwards the first product barcode in each batch while on.
nonisolated private final class MetadataDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    var isOn = false
    var onCode: ((String) -> Void)?

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isOn else { return }
        for object in metadataObjects {
            if let code = (object as? AVMetadataMachineReadableCodeObject)?.stringValue, !code.isEmpty {
                isOn = false
                onCode?(code)
                return
            }
        }
    }
}

/// Reads a product barcode in a still photo (Barcode mode's library button).
nonisolated enum PhotoBarcodeReader {
    static func code(in data: Data) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.ean13, .ean8, .upce, .code128]
            let handler = VNImageRequestHandler(data: data)
            try? handler.perform([request])
            return request.results?.compactMap(\.payloadStringValue).first { !$0.isEmpty }
        }.value
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
