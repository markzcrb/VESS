import AVFoundation
import OSLog
import SwiftUI
import UIKit
import Vision

/// How long a closed camera stays configured, so opening Photo again
/// within it only costs `startRunning`. Pure.
nonisolated struct CameraKeepAlive: Equatable, Sendable {
    static let interval: TimeInterval = 30

    private(set) var isInUse = false
    private(set) var releasedAt: Date?
    /// Bumped on every acquire and release, so an old teardown can't win.
    private(set) var generation = 0

    mutating func acquire() {
        isInUse = true
        releasedAt = nil
        generation += 1
    }

    /// Returns the token a later teardown check needs.
    mutating func release(at date: Date) -> Int {
        isInUse = false
        releasedAt = date
        generation += 1
        return generation
    }

    /// True only for the latest release, still unused, after `interval`.
    func shouldTearDown(token: Int, now: Date) -> Bool {
        guard !isInUse, token == generation, let releasedAt else { return false }
        return now.timeIntervalSince(releasedAt) >= Self.interval
    }
}

/// The one camera for Photo (I02, M01), shared by every Add sheet: photos
/// for estimates, and barcodes from the same live session (metadata
/// output), so switching Meal, Menu and Barcode never restarts it.
/// Everything AVFoundation runs on the box's serial session queue, never on
/// main. The session is built ahead (`prewarm`, when Add opens), started
/// when Photo shows, stopped when it goes, and kept configured for 30 s so
/// reopening is quick. Logged as category "PhotoCamera".
@Observable
final class PhotoCameraController {
    static let shared = PhotoCameraController()

    enum State: Equatable { case idle, running, unavailable, denied, interrupted }

    private(set) var state: State = .idle
    /// The preview has shown a frame; it fades in then, over black.
    private(set) var hasFrame = false
    private(set) var hasFlash = false
    private(set) var hasTorch = false

    /// The light button's state. Meal and Menu: off, flash (at the
    /// shutter) or torch (a steady light for the preview). Barcode: off or
    /// torch. Remembered per mode until Photo closes.
    enum Light: String, Sendable { case off, flash, torch }
    private(set) var light: Light = .off
    @ObservationIgnored private var lightByMode: [String: Light] = [:]
    @ObservationIgnored private var modeKey = "meal"

    /// A barcode seen while `detectsBarcodes` is on. Detection pauses after
    /// each code until it's turned on again.
    @ObservationIgnored var onBarcode: ((String) -> Void)?
    var detectsBarcodes = false {
        didSet { box.setDetecting(detectsBarcodes) }
    }
    /// Barcode mode: the metadata output looks for codes only then.
    private(set) var isBarcodeMode = false

    @ObservationIgnored let box = CaptureBox()
    /// One preview for the app's life, attached to the session once, so
    /// opening Photo never attaches a layer while the session starts.
    @ObservationIgnored private(set) lazy var previewView: CameraPreview.PreviewView = {
        let view = CameraPreview.PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.observation = view.previewLayer.observe(\.isPreviewing, options: [.new]) { [weak self] layer, _ in
            let isPreviewing = layer.isPreviewing
            let owner = self
            Task { @MainActor in owner?.previewing(isPreviewing) }
        }
        return view
    }()
    @ObservationIgnored private var keepAlive = CameraKeepAlive()
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
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: box.session, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue ?? -1
            Self.logger.info("session interrupted, reason \(reason, privacy: .public)")
            MainActor.assumeIsolated { self?.interrupted() }
        })
        observers.append(center.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: nil, queue: .main) { [box] _ in
            box.resumeContinuousFocus()
        })
        for name in [AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
            observers.append(center.addObserver(forName: name, object: box.session, queue: .main) { [weak self] note in
                Self.logger.info("session: \(note.name.rawValue, privacy: .public); starting again if in use")
                MainActor.assumeIsolated { self?.resumeIfInUse() }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Builds the session ahead (input, outputs, preset), without starting
    /// it. Only with permission already given: otherwise Photo asks first.
    func prewarm() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        attachPreview()
        box.prepare { _ in }
    }

    private func attachPreview() {
        if previewView.previewLayer.session == nil { previewView.previewLayer.session = box.session }
    }

    /// Photo is on screen: asks for permission if it was never asked, then
    /// starts the (prepared) session on the session queue.
    func acquire() async {
        keepAlive.acquire()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { state = .denied; return }
        case .denied, .restricted:
            state = .denied
            return
        default:
            break
        }
        guard keepAlive.isInUse else { return }
        attachPreview()
        let result = await box.start()
        CameraTiming.mark("start")
        hasFlash = result.hasFlash
        hasTorch = result.hasTorch
        box.setDetecting(detectsBarcodes)
        // Closed while it was starting: stop again.
        guard keepAlive.isInUse else { box.stop(); return }
        state = result.ok ? .running : (result.interrupted ? .interrupted : .unavailable)
        // The torch needs a running session; bring back the mode's light.
        if light == .torch { box.setTorch(true) }
        // Flash support can show up a moment after a cold start; look again.
        Task {
            try? await Task.sleep(for: .seconds(1))
            let support = await box.lightSupport()
            hasFlash = support.flash
            hasTorch = support.torch
        }
        Self.logger.info("start: \(String(describing: self.state), privacy: .public)")
    }

    /// Photo has gone (closed, another type, a photo taken, background):
    /// the light goes off and the session stops on its queue. It stays
    /// configured for `CameraKeepAlive.interval`, then is taken apart.
    func release() {
        guard keepAlive.isInUse else { return }
        box.setTorch(false)
        light = .off
        lightByMode = [:]
        detectsBarcodes = false
        box.stop()
        state = .idle
        hasFrame = false
        let token = keepAlive.release(at: .now)
        Task {
            try? await Task.sleep(for: .seconds(CameraKeepAlive.interval))
            guard keepAlive.shouldTearDown(token: token, now: .now) else { return }
            box.tearDown()
            Self.logger.info("session taken apart after \(Int(CameraKeepAlive.interval), privacy: .public) s unused")
        }
    }

    /// The preview layer started or stopped showing frames.
    func previewing(_ isPreviewing: Bool) {
        if isPreviewing { CameraTiming.mark("frame") }
        hasFrame = isPreviewing && keepAlive.isInUse
    }

    private func interrupted() {
        guard keepAlive.isInUse else { return }
        state = .interrupted
    }

    private func resumeIfInUse() {
        guard keepAlive.isInUse else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard keepAlive.isInUse else { return }
            let result = await box.start()
            state = result.ok ? .running : (result.interrupted ? .interrupted : .unavailable)
        }
    }

    /// The lights this mode can use, in the order the button cycles them.
    var availableLights: [Light] {
        var lights: [Light] = [.off]
        if !isBarcodeMode, hasFlash { lights.append(.flash) }
        if hasTorch { lights.append(.torch) }
        return lights
    }

    /// The light button: the next available state.
    func cycleLight() {
        let lights = availableLights
        guard lights.count > 1 else { return }
        let next = lights[((lights.firstIndex(of: light) ?? 0) + 1) % lights.count]
        setLight(next)
    }

    private func setLight(_ new: Light) {
        light = new
        lightByMode[modeKey] = new
        box.setTorch(new == .torch)
    }

    /// Meal, Menu or Barcode. The old mode's light goes off; the new one's
    /// remembered state comes back. Codes are looked for only in Barcode.
    func switchMode(_ key: String, barcode: Bool) {
        modeKey = key
        if isBarcodeMode != barcode {
            isBarcodeMode = barcode
            box.setBarcodeMode(barcode)
        }
        let remembered = lightByMode[key] ?? .off
        light = availableLights.contains(remembered) ? remembered : .off
        box.setTorch(light == .torch)
    }

    /// Tap to focus: a point in the preview's coordinates.
    func focus(atPreviewPoint point: CGPoint) {
        let devicePoint = previewView.previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        box.focus(at: devicePoint)
    }

    /// Barcode mode reads codes only inside the guide (a rect in the
    /// preview's coordinates).
    func setScanRect(_ rect: CGRect) {
        guard hasFrame else { return }
        box.setRectOfInterest(previewView.previewLayer.metadataOutputRectConverted(fromLayerRect: rect))
    }

    /// The photo's data (HEIC or JPEG), or `nil` if it failed.
    func capture() async -> Data? {
        await box.capture(flash: light == .flash && hasFlash)
    }
}

/// Owns the session and its queue. Everything runs on `queue`.
nonisolated final class CaptureBox: @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let metadata = AVCaptureMetadataOutput()
    private let metadataDelegate = MetadataDelegate()
    private let queue = DispatchQueue(label: "VESS.photoCamera", qos: .userInitiated)
    private var isConfigured = false
    /// Found once, kept for the app's life.
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var isBarcodeMode = false
    /// 1× as the user sees it: the virtual device's first switch-over factor.
    private var baseZoom: CGFloat = 1
    /// Bumped by each tap to focus, so an older return to continuous focus
    /// doesn't undo a newer tap.
    private var focusGeneration = 0
    private var delegates: [Int64: PhotoDelegate] = [:]
    /// Called on the camera's queue with each product barcode while detecting.
    var onCode: ((String) -> Void)? {
        get { metadataDelegate.onCode }
        set { metadataDelegate.onCode = newValue }
    }

    /// Product barcodes, as the scanner reads them.
    static let barcodeTypes: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128]

    struct StartResult: Sendable {
        var ok: Bool
        var interrupted: Bool
        var hasFlash: Bool
        var hasTorch: Bool
    }

    /// Configures the session once: input, photo output, metadata output
    /// (no types until Barcode mode), preset. Doesn't start it.
    func prepare(_ done: @escaping @Sendable (Bool) -> Void) {
        queue.async { done(self.configureIfNeeded()) }
    }

    /// On `queue`.
    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        if device == nil { device = Self.backCamera() }
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        // Sharp photos: the largest size the format offers, balanced
        // processing; they're made smaller before upload, as before.
        if let largest = device.activeFormat.supportedMaxPhotoDimensions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            output.maxPhotoDimensions = largest
        }
        output.maxPhotoQualityPrioritization = .balanced
        baseZoom = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1
        if session.canAddOutput(metadata) {
            session.addOutput(metadata)
            metadata.setMetadataObjectsDelegate(metadataDelegate, queue: queue)
            applyBarcodeTypes()
        }
        self.input = input
        isConfigured = true
        return true
    }

    func start() async -> StartResult {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.configureIfNeeded() else {
                    continuation.resume(returning: StartResult(ok: false, interrupted: false, hasFlash: false, hasTorch: false))
                    return
                }
                if !self.session.isRunning { self.session.startRunning() }
                self.continuousFocus()
                continuation.resume(returning: StartResult(
                    ok: self.session.isRunning, interrupted: self.session.isInterrupted,
                    hasFlash: self.output.supportedFlashModes.contains(.on),
                    hasTorch: self.device?.hasTorch == true
                ))
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func lightSupport() async -> (flash: Bool, torch: Bool) {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: (self.output.supportedFlashModes.contains(.on), self.device?.hasTorch == true))
            }
        }
    }

    /// After the keep-alive: inputs and outputs go; the device stays known.
    func tearDown() {
        queue.async {
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach(self.session.removeInput)
            self.session.outputs.forEach(self.session.removeOutput)
            self.session.commitConfiguration()
            self.input = nil
            self.isConfigured = false
        }
    }

    func setDetecting(_ on: Bool) {
        queue.async { self.metadataDelegate.isOn = on }
    }

    /// Codes are looked for only in Barcode mode; the photo output is never
    /// touched when the mode changes.
    func setBarcodeMode(_ on: Bool) {
        queue.async {
            self.isBarcodeMode = on
            guard self.isConfigured else { return }
            self.applyBarcodeTypes()
            if !on { self.metadata.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1) }
            if self.session.isRunning { self.continuousFocus() }
        }
    }

    /// On `queue`.
    private func applyBarcodeTypes() {
        metadata.metadataObjectTypes = isBarcodeMode ? Self.barcodeTypes.filter(metadata.availableMetadataObjectTypes.contains) : []
    }

    /// The back virtual camera when there is one, so iOS can switch to the
    /// ultra-wide for close-ups (food, small barcodes); else the wide.
    private static func backCamera() -> AVCaptureDevice? {
        for type: AVCaptureDevice.DeviceType in [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera] {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
        }
        return nil
    }

    /// On `queue`, after `startRunning`: continuous focus and exposure at
    /// the centre, the mode's zoom and focus range.
    private func continuousFocus() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.isSubjectAreaChangeMonitoringEnabled = true
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = isBarcodeMode ? .near : .none }
        device.videoZoomFactor = min(max(isBarcodeMode ? baseZoom * barcodeZoom(device) : baseZoom, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        device.unlockForConfiguration()
        if CameraTiming.isPrinting {
            print("CameraFocus device=\(device.deviceType.rawValue) zoom=\(device.videoZoomFactor) base=\(baseZoom) barcode=\(isBarcodeMode) near=\(device.autoFocusRangeRestriction == .near) minFocus=\(device.minimumFocusDistance)mm")
        }
    }

    /// Apple's AVCamBarcode formula: zoom so a 20 mm code fills the guide's
    /// width at the closest focus distance; at most 2× as the user sees it.
    private func barcodeZoom(_ device: AVCaptureDevice) -> CGFloat {
        let wide = device.constituentDevices.first { $0.deviceType == .builtInWideAngleCamera } ?? device
        let minimumFocus = Float(wide.minimumFocusDistance)
        guard minimumFocus > 0 else { return 1 }
        // The field of view at 1×: the virtual device's format is the ultra-wide's.
        let halfFOV = atan(tan(device.activeFormat.videoFieldOfView * .pi / 360) / Float(baseZoom))
        let codeSize: Float = 20
        let filled = codeSize / Float(BarcodeScanArea.widthFraction)
        let subjectDistance = filled / tan(halfFOV)
        guard subjectDistance < minimumFocus else { return 1 }
        return CGFloat(min(minimumFocus / subjectDistance, 2))
    }

    /// Tap to focus: focus and expose there, then continuous again after
    /// 3 s (or sooner, when the scene changes).
    func focus(at point: CGPoint) {
        queue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
            self.focusGeneration += 1
            let generation = self.focusGeneration
            self.queue.asyncAfter(deadline: .now() + 3) {
                guard generation == self.focusGeneration, self.session.isRunning else { return }
                self.continuousFocus()
            }
        }
    }

    /// The scene changed after a tap: continuous focus again.
    func resumeContinuousFocus() {
        queue.async {
            guard self.session.isRunning else { return }
            self.focusGeneration += 1
            self.continuousFocus()
        }
    }

    func setRectOfInterest(_ rect: CGRect) {
        queue.async {
            guard self.isConfigured, rect.width > 0, rect.height > 0 else { return }
            self.metadata.rectOfInterest = rect
        }
    }

    /// Torch on or off; skipped while the system holds it back (heat).
    func setTorch(_ on: Bool) {
        queue.async {
            guard let device = self.device, device.hasTorch, device.isTorchAvailable || !on,
                  (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            if CameraTiming.isPrinting {
                // Read back after a moment: is the LED really lit?
                self.queue.asyncAfter(deadline: .now() + 0.3) { print("CameraLight torch requested=\(on) active=\(device.isTorchActive)") }
            }
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
                settings.maxPhotoDimensions = self.output.maxPhotoDimensions
                settings.photoQualityPrioritization = .balanced
                if flash, self.output.supportedFlashModes.contains(.on) { settings.flashMode = .on }
                else if self.output.supportedFlashModes.contains(.off) { settings.flashMode = .off }
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

/// Barcode mode's guide inside the camera frame, as fractions of it. The
/// guide is drawn from it and codes are read only inside it.
nonisolated enum BarcodeScanArea {
    static let widthFraction: CGFloat = 0.78

    static func rect(in size: CGSize) -> CGRect {
        let width = size.width * widthFraction
        let height = min(size.height * 0.34, width * 0.55)
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
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
        if CameraTiming.isPrinting {
            let size = photo.resolvedSettings.photoDimensions
            print("CameraLight photo flashFired=\(photo.resolvedSettings.isFlashEnabled) size=\(size.width)x\(size.height)")
        }
        finished = true
        completion(error == nil ? photo.fileDataRepresentation() : nil)
    }
}

/// The live preview: hosts the camera's one preview view.
struct CameraPreview: UIViewRepresentable {
    let camera: PhotoCameraController

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .black
        let preview = camera.previewView
        preview.frame = host.bounds
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(preview)
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        // Another Add sheet may have taken the shared view; take it back.
        let preview = camera.previewView
        if preview.superview !== host {
            preview.frame = host.bounds
            host.addSubview(preview)
        }
    }

    final class PreviewView: UIView {
        var observation: NSKeyValueObservation?
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
