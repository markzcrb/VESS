import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// F01–F02: scan a product barcode with the camera. It scans on its own;
/// a found product opens "Product found" (F03). Typing the number is always
/// one tap away, including when the camera is off or unsupported.
struct BarcodeScannerView: View {
    @Environment(FoodLookupService.self) private var lookup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let day: Date
    @Binding var meal: MealType
    /// Food was logged: close the whole Add flow.
    let onLogged: () -> Void
    let onTypeNumber: () -> Void
    /// Not found: add it yourself. Receives the scanned code.
    let onAddManually: (String) -> Void
    /// When set (Pantry), a found product is handed back and the scanner
    /// closes, instead of opening Product found for logging.
    var onProduct: ((Food) -> Void)?

    private enum Phase: Equatable {
        case starting
        case scanning
        case reading(String)
        case notFound(String)
        case failed(String, FoodProviderError)
        case cameraDenied
        case unsupported
    }

    @State private var phase: Phase = .starting
    @State private var found: Food?
    /// The torch and scanner restarts; torch state comes from the hardware.
    @State private var controller = ScannerController()

    var body: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xl) {
            topBar
            Text(title)
                .vessTextStyle(.editorialL)
                .foregroundStyle(VESSColor.text)
                .accessibilityAddTraits(.isHeader)
                .contentTransition(.opacity)
            preview
            status
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VESSSpacing.screenInset)
        .padding(.top, VESSSpacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .vessScreenBackground()
        .animation(reduceMotion ? nil : VESSMotion.selection, value: phase)
        .vessHaptic(.success, trigger: phase) { _, new in
            if case .reading = new { true } else { false }
        }
        .task { await start() }
        .sheet(item: $found, onDismiss: { phase = .scanning }) { food in
            ProductFoundSheet(food: food, day: day, meal: $meal, onLogged: onLogged)
        }
        .onDisappear { controller.setTorch(false) }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            VESSIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                .accessibilityIdentifier("scanner.close")
            Spacer()
            if (phase == .scanning || isReading) && controller.hasTorch {
                VESSIconButton(
                    systemImage: controller.isTorchOn ? "bolt.fill" : "bolt",
                    label: controller.isTorchOn ? "Turn light off" : "Turn light on",
                    isFilled: controller.isTorchOn
                ) {
                    controller.setTorch(!controller.isTorchOn)
                }
                // Off while the system holds the torch back (for example heat).
                .disabled(!controller.isTorchAvailable && !controller.isTorchOn)
                .accessibilityIdentifier("scanner.torch")
            }
        }
    }

    private var title: LocalizedStringResource {
        switch phase {
        case .starting, .scanning: "Point at a barcode"
        case .reading: "Barcode detected"
        case .notFound: "No product found"
        case .failed: "Couldn't look it up"
        case .cameraDenied: "The camera is off for VESS"
        case .unsupported: "Scanning isn't available here"
        }
    }

    /// The camera inside a rounded card, with the guide frame on top.
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                .fill(VESSColor.card)
            if showsCamera {
                BarcodeDataScanner(controller: controller) { code in detected(code) }
                    .clipShape(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
                    .accessibilityHidden(true)
            } else if phase == .cameraDenied || phase == .unsupported {
                Image(systemName: "camera")
                    .font(.largeTitle)
                    .foregroundStyle(VESSColor.decorative)
                    .accessibilityHidden(true)
            }
            if phase == .scanning || phase == .starting || isReading {
                RoundedRectangle(cornerRadius: VESSRadius.thumbnail, style: .continuous)
                    .strokeBorder(VESSColor.text, lineWidth: 1.5)
                    .padding(.horizontal, VESSSpacing.huge + VESSSpacing.sm)
                    .padding(.vertical, VESSSpacing.huge * 2)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(0.98, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera preview")
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .starting, .scanning:
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                Text("Hold steady. It scans on its own.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.text)
                typeNumberButton
            }
        case .reading(let code):
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                HStack(spacing: VESSSpacing.sm) {
                    Text("Reading barcode")
                        .vessTextStyle(.bodyMStrong)
                        .foregroundStyle(VESSColor.text)
                    ProgressView()
                }
                Text(verbatim: Self.grouped(code))
                    .vessTextStyle(.bodyM)
                    .monospacedDigit()
                    .foregroundStyle(VESSColor.secondaryText)
                    .accessibilityIdentifier("scanner.code")
            }
        case .notFound(let code):
            message(
                // Non-breaking spaces keep the number on one line.
                Text("Nothing on Open Food Facts for \(Self.grouped(code).replacingOccurrences(of: " ", with: "\u{00A0}")). You can add it yourself."),
                primary: ("Add manually", { onAddManually(code) }),
                secondary: ("Scan again", { phase = .scanning })
            )
        case .failed(_, let error):
            message(
                Text(BarcodeLookupView.message(for: error)),
                primary: ("Scan again", { phase = .scanning }),
                secondary: ("Type barcode number", onTypeNumber)
            )
        case .cameraDenied:
            message(
                Text("To scan, allow camera access in Settings. You can also type the number under the barcode."),
                primary: ("Open Settings", openSettings),
                secondary: ("Type barcode number", onTypeNumber)
            )
        case .unsupported:
            message(
                Text("This device can't scan barcodes. Type the number under the barcode instead."),
                primary: ("Type barcode number", onTypeNumber),
                secondary: nil
            )
        }
    }

    private var typeNumberButton: some View {
        Button("Type barcode number", action: onTypeNumber)
            .buttonStyle(.vessSecondary)
            .accessibilityIdentifier("scanner.typeNumber")
    }

    private func message(
        _ text: Text,
        primary: (LocalizedStringResource, () -> Void),
        secondary: (LocalizedStringResource, () -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            text
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: primary.1) { Text(primary.0) }
                .buttonStyle(.vessPrimary)
            if let secondary {
                Button(action: secondary.1) { Text(secondary.0) }
                    .buttonStyle(.vessSecondary)
            }
        }
    }

    // MARK: Scanning

    private var isReading: Bool {
        if case .reading = phase { true } else { false }
    }

    private var showsCamera: Bool {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else { return false }
        return phase == .scanning || isReading
    }

    private func start() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-demoBarcode") || arguments.contains("-demoBarcodeNotFound") {
            await runDemoScan()
            return
        }
        #endif
        guard DataScannerViewController.isSupported else {
            phase = .unsupported
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            phase = .scanning
        case .notDetermined:
            phase = await AVCaptureDevice.requestAccess(for: .video) ? .scanning : .cameraDenied
        default:
            phase = .cameraDenied
        }
    }

    private func detected(_ code: String) {
        guard phase == .scanning else { return }
        phase = .reading(code)
        Task {
            switch await lookup.lookUp(barcode: code) {
            case .success(let food):
                handle(food)
            case .failure(.notFound):
                phase = .notFound(code)
            case .failure(let error):
                phase = .failed(code, error)
            }
        }
    }

    #if DEBUG
    /// `-demoBarcode`: the simulator has no camera, so captures of F01–F03
    /// step through a fixed scan of the DEBUG demo product.
    /// `-demoBarcodeNotFound` ends in "No product found" (F05) instead.
    private func runDemoScan() async {
        phase = .scanning
        try? await Task.sleep(for: .seconds(3))
        if ProcessInfo.processInfo.arguments.contains("-demoBarcodeNotFound") {
            let code = "4000000000006"
            phase = .reading(code)
            try? await Task.sleep(for: .seconds(2))
            phase = .notFound(code)
            return
        }
        guard let code = MockData.barcodeDemo.barcode else { return }
        phase = .reading(code)
        try? await Task.sleep(for: .seconds(3))
        handle(MockData.barcodeDemo)
    }
    #endif

    private func handle(_ food: Food) {
        if let onProduct {
            onProduct(food)
            dismiss()
        } else {
            found = food
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    /// EAN-13 as printed: "5 760466 112233". Other lengths stay as they are.
    static func grouped(_ code: String) -> String {
        guard code.count == 13, code.allSatisfy(\.isNumber) else { return code }
        let digits = Array(code)
        return "\(digits[0]) \(String(digits[1...6])) \(String(digits[7...12]))"
    }
}

/// VisionKit's live scanner, limited to product barcodes. `ScannerController`
/// starts it, restarts it when it stops, and owns the torch.
private struct BarcodeDataScanner: UIViewControllerRepresentable {
    let controller: ScannerController
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        controller.attach(scanner)
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        coordinator.controller.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let controller: ScannerController
        var onCode: (String) -> Void

        init(controller: ScannerController, onCode: @escaping (String) -> Void) {
            self.controller = controller
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            controller.scannerBecameUnavailable(error)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue {
                    onCode(code)
                    return
                }
            }
        }
    }
}
