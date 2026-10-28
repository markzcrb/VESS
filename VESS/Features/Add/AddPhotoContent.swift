import PhotosUI
import SwiftUI
import UIKit

/// Photo in the Add sheet (I02–I08, M01): take or pick a photo, send it
/// once for an estimate, then review every item before anything is logged.
/// Menu mode reads a menu page instead (M02). Barcode mode reads product
/// barcodes in the same live camera (Open Food Facts, no AI, no quota).
/// The photo is made smaller, stripped of metadata, and dropped once the
/// answer is in. The last mode is remembered.
struct AddPhotoContent: View {
    let day: Date
    @Binding var meal: MealType
    /// The last menu read, kept by the Add sheet until it closes.
    @Binding var menu: MenuScanResult?
    let onSearchInstead: () -> Void
    /// Barcode: type the number instead.
    let onTypeNumber: () -> Void
    /// Barcode not found: add the product yourself, with its code.
    let onAddManually: (String) -> Void
    let onLogged: () -> Void

    /// M01's segment.
    enum Mode: String, Hashable { case meal, menu, barcode }

    /// Barcode mode's progress.
    private enum Scan: Equatable {
        case scanning
        case reading(String)
        case notFound(String)
        case failed(String, FoodProviderError)
        /// A photo from the library had no barcode.
        case noCodeInPhoto
    }

    @Environment(AccountStore.self) private var account
    @Environment(AIConsentStore.self) private var consent
    @Environment(LocalStore.self) private var store
    @Environment(FoodLookupService.self) private var lookup
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.vessHaptics) private var haptics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage("photo.remaining") private var remaining = -1
    @AppStorage("photo.remainingDay") private var remainingDay = ""
    /// The mode used last; Photo opens in it.
    @AppStorage("photo.mode") private var storedMode = Mode.meal.rawValue

    private enum Phase: Equatable {
        case camera
        case looking
        case review
        case empty(String?)
        case failed(BackendError)
    }

    @State private var camera = PhotoCameraController()
    @State private var phase: Phase = .camera
    /// Shown while it's being looked at, then dropped with the answer.
    @State private var lookingImage: UIImage?
    @State private var items: [EstimatedItem] = []
    @State private var note: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingPhoto: Data?
    @State private var showConsent = false
    @State private var showSignIn = false
    @State private var showError = false
    /// Set by the first Save, so a quick second tap can't log twice.
    @State private var isSaved = false
    @State private var showMenu = false
    @State private var scan: Scan = .scanning
    @State private var found: Food?
    /// The frame's one flash when a code is found.
    @State private var flash = false

    private var mode: Mode { Mode(rawValue: storedMode) ?? .meal }

    var body: some View {
        Group {
            if !account.isSignedIn && mode != .barcode {
                signedOut
            } else {
                switch phase {
                case .camera: cameraView
                case .looking: looking
                case .review:
                    PhotoReviewView(items: $items, meal: $meal, note: note, day: day, onSave: save)
                case .empty(let note): emptyResult(note)
                case .failed(let error): failed(error)
                }
            }
        }
        .sheet(isPresented: $showSignIn) { AISignInSheet() }
        .vessAIConsent(.photo, isPresented: $showConsent) {
            if let pendingPhoto { send(pendingPhoto) }
        }
        .onChange(of: showConsent) { _, isShown in
            // "Not now": nothing is sent, and the photo is dropped.
            if !isShown, !consent.isGranted(.photo) { pendingPhoto = nil }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    if mode == .barcode { await readBarcode(inPhoto: data) } else { use(data) }
                }
                pickerItem = nil
            }
        }
        .sheet(item: $found, onDismiss: resumeScanning) { food in
            ProductFoundSheet(food: food, day: day, meal: $meal, onLogged: onLogged)
        }
        .vessErrorAlert(isPresented: $showError)
        .navigationDestination(isPresented: $showMenu) {
            if let menu {
                MenuResultsView(result: menu, day: day, onLogged: onLogged)
            }
        }
        .onAppear {
            camera.onBarcode = { code in detected(code) }
            updateDetection()
        }
        .onChange(of: storedMode) { _, _ in
            if mode != .barcode { camera.setTorch(false) }
            scan = .scanning
            updateDetection()
        }
        .task { await loadRemaining() }
        .onDisappear { camera.stop() }
    }

    // MARK: States

    private var signedOut: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                modePicker
                Text("Photo estimates need an account. Only for Coach, photo estimates and AI Chef; your log stays on this iPhone. Barcodes work without one.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Sign in") { showSignIn = true }
                    .buttonStyle(.vessPrimary)
                    .accessibilityIdentifier("photo.signIn")
                Button("Search instead", action: onSearchInstead)
                    .buttonStyle(.vessSecondary)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
        }
    }

    /// No estimates left today: in Meal and Menu the camera isn't started
    /// (saves battery) and the shutter and library are off. Barcode needs none.
    private var isOutOfEstimates: Bool { remainingToday == 0 && mode != .barcode }

    /// The shutter row's height, so the viewfinder leaves room for it.
    private static let controlsHeight: CGFloat = 84
    /// The Meal / Menu / Barcode segment and the gap under it.
    private static let segmentHeight: CGFloat = VESSHitTarget.minimum + VESSSpacing.md

    private var modePicker: some View {
        VESSSegmented(selection: Binding(get: { mode }, set: { storedMode = $0.rawValue }),
                      options: [(.meal, "Meal"), (.menu, "Menu"), (.barcode, "Barcode")])
            .accessibilityIdentifier("photo.mode")
    }

    /// Always the full content width; 3:4 when there's room, otherwise as
    /// tall as fits above the shutter row (a little wider than 3:4).
    static func viewfinderSize(in available: CGSize) -> CGSize {
        let width = max(available.width - 2 * VESSSpacing.screenInset, 0)
        let room = available.height - controlsHeight - VESSSpacing.md * 3
        return CGSize(width: width, height: max(min(width * 4 / 3, room), 160))
    }

    private var cameraView: some View {
        // The footer has its own space at the bottom, above the safe area;
        // the viewfinder takes what's left above the shutter row.
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let size = Self.viewfinderSize(in: CGSize(width: proxy.size.width, height: proxy.size.height - Self.segmentHeight))
                ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: VESSSpacing.md) {
                        modePicker

                        // Full width at 3:4, as tall as fits above the shutter row.
                        viewfinder
                            .frame(width: size.width, height: size.height)
                            .frame(maxWidth: .infinity)

                        controls

                        if mode == .barcode { barcodeStatus.id(Self.statusID) }

                        // At accessibility sizes the footer ends the page
                        // instead of taking half the screen.
                        if dynamicTypeSize.isAccessibilitySize { footer.padding(.horizontal, -VESSSpacing.screenInset) }

                        #if DEBUG
                        if ProcessInfo.processInfo.arguments.contains("-aiMock"), mode != .barcode, !isOutOfEstimates {
                            Button("Use a sample photo (debug)") { use(Self.samplePhoto()) }
                                .buttonStyle(.vessSecondary)
                                .accessibilityIdentifier("photo.sample")
                        }
                        if ProcessInfo.processInfo.arguments.contains("-demoBarcode"), mode == .barcode, scan == .scanning {
                            Button("Use a sample barcode (debug)") { detected(MockData.barcodeDemo.barcode ?? "") }
                                .buttonStyle(.vessSecondary)
                                .accessibilityIdentifier("photo.sampleBarcode")
                        }
                        #endif
                    }
                    .padding(.horizontal, VESSSpacing.screenInset)
                    .vessContentTop(VESSSpacing.md)
                    .padding(.bottom, VESSSpacing.md)
                }
                // A barcode message comes into view as it appears.
                .onChange(of: scan) { _, new in
                    guard new != .scanning, !isReading(new) else { return }
                    withAnimation(reduceMotion ? nil : .snappy) { scroller.scrollTo(Self.statusID, anchor: .bottom) }
                }
                }
            }
            // Nothing scrolls out under the footer.
            .clipped()
            if !dynamicTypeSize.isAccessibilitySize { footer }
        }
        // One session for all three modes: switching never restarts it.
        .task(id: isOutOfEstimates) {
            if isOutOfEstimates { camera.stop() } else { await camera.start() }
        }
    }

    private static let statusID = "photo.barcodeStatus"

    private func isReading(_ scan: Scan) -> Bool {
        if case .reading = scan { true } else { false }
    }

    private var pillText: Text {
        switch mode {
        case .meal: return Text("Fit the whole plate in the frame.")
        case .menu: return Text("Fit the whole menu page in the frame")
        case .barcode:
            if case .reading(let code) = scan {
                return Text("Looking up \(BarcodeScannerView.grouped(code).replacingOccurrences(of: " ", with: "\u{00A0}"))…")
            }
            return Text("Point at the barcode")
        }
    }

    private var viewfinder: some View {
        let shape = RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
        return ZStack {
            shape.fill(VESSColor.fill)
            if isOutOfEstimates {
                VStack(spacing: VESSSpacing.md) {
                    Text("No estimates left today · \(AIQuotaText.resetsShort(after: AppClock.now))")
                        .vessTextStyle(.bodyM)
                        .foregroundStyle(VESSColor.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Log manually", action: onSearchInstead)
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("photo.logManually")
                }
                .padding(VESSSpacing.xl)
            } else {
                switch camera.state {
                case .running:
                    CameraPreview(session: camera.box.session)
                        .clipShape(shape)
                case .idle:
                    ProgressView()
                case .unavailable, .denied:
                    VStack(spacing: VESSSpacing.sm) {
                        Image(systemName: "camera")
                            .font(.title2)
                            .foregroundStyle(VESSColor.secondaryText)
                            .accessibilityHidden(true)
                        Text(camera.state == .denied ? "Camera access is off for UMEVA. Pick a photo, or turn it on in Settings." : "The camera isn't available here. Pick a photo instead.")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .padding(.horizontal, VESSSpacing.lg)
                    .accessibilityShowsLargeContentViewer()
                }
                if mode == .barcode { BarcodeGuide() }
            }
            // The frame flashes once when a code is found.
            shape.fill(VESSColor.text)
                .opacity(flash ? 0.35 : 0)
                .allowsHitTesting(false)
        }
        // Nothing inside spills past the frame.
        .clipShape(shape)
        .overlay(alignment: .top) {
            if !isOutOfEstimates {
                pillText
                    .accessibilityShowsLargeContentViewer()
                    .vessTextStyle(.caption)
                    .foregroundStyle(VESSColor.text)
                    // One line, so it never covers the frame's content.
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .padding(.horizontal, VESSSpacing.sm)
                    .padding(.vertical, VESSSpacing.xxs + 2)
                    .background(VESSColor.background.opacity(0.7), in: Capsule())
                    .padding(.top, VESSSpacing.sm)
                    .padding(.horizontal, VESSSpacing.sm)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("photo.pill")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var controls: some View {
        HStack {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Photos", systemImage: "photo.on.rectangle")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(VESSColor.text)
                    .frame(width: VESSSize.addButton, height: VESSSize.addButton)
                    .background(VESSColor.fill, in: Circle())
            }
            .disabled(isOutOfEstimates)
            .opacity(isOutOfEstimates ? 0.4 : 1)
            .accessibilityLabel(mode == .barcode ? "Scan a barcode from a photo" : "Pick a photo")
            .accessibilityIdentifier("photo.pick")
            Spacer()
            // Barcode mode reads on its own: no shutter (its space stays).
            Button(action: shoot) {
                Circle()
                    .fill(VESSColor.accentFill)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().strokeBorder(VESSColor.borderStrong, lineWidth: 4).padding(-6))
            }
            .buttonStyle(.plain)
            .disabled(camera.state != .running || isOutOfEstimates || mode == .barcode)
            .opacity(mode == .barcode ? 0 : (camera.state == .running && !isOutOfEstimates ? 1 : 0.4))
            .accessibilityHidden(mode == .barcode)
            .accessibilityLabel("Take photo")
            .accessibilityIdentifier("photo.shutter")
            Spacer()
            lightButton
        }
        // The symbols stop growing so they stay inside their circles.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: Self.controlsHeight)
    }

    /// The photo flash in Meal and Menu; the torch in Barcode.
    @ViewBuilder
    private var lightButton: some View {
        if mode == .barcode {
            Button { camera.setTorch(!camera.isTorchOn) } label: {
                Image(systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.title3)
                    .foregroundStyle(VESSColor.text)
                    .frame(width: VESSSize.addButton, height: VESSSize.addButton)
                    .background(VESSColor.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(camera.hasTorch ? 1 : 0)
            .disabled(!camera.hasTorch)
            .accessibilityLabel(camera.isTorchOn ? "Turn light off" : "Turn light on")
            .accessibilityIdentifier("photo.torch")
        } else {
            Button { camera.isFlashOn.toggle() } label: {
                Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash")
                    .font(.title3)
                    .foregroundStyle(VESSColor.text)
                    .frame(width: VESSSize.addButton, height: VESSSize.addButton)
                    .background(VESSColor.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(camera.hasFlash && !isOutOfEstimates ? 1 : 0)
            .disabled(!camera.hasFlash || isOutOfEstimates)
            .accessibilityLabel(camera.isFlashOn ? "Flash on" : "Flash off")
        }
    }

    /// Not found, a failed look-up, or no code in a photo: the scanner's flows.
    @ViewBuilder
    private var barcodeStatus: some View {
        switch scan {
        case .scanning, .reading:
            EmptyView()
        case .notFound(let code):
            barcodeMessage(
                // Non-breaking spaces keep the number on one line.
                Text("Nothing on Open Food Facts for \(BarcodeScannerView.grouped(code).replacingOccurrences(of: " ", with: "\u{00A0}")). You can add it yourself."),
                primary: ("Add manually", { onAddManually(code) }),
                secondary: ("Scan again", resumeScanning)
            )
            .accessibilityIdentifier("photo.barcodeNotFound")
        case .failed(_, let error):
            barcodeMessage(
                Text(BarcodeLookupView.message(for: error)),
                primary: ("Scan again", resumeScanning),
                secondary: ("Type barcode number", onTypeNumber)
            )
        case .noCodeInPhoto:
            barcodeMessage(
                Text("No barcode found in that photo. Try one where the barcode is sharp and fills more of the picture."),
                primary: ("Scan again", resumeScanning),
                secondary: ("Type barcode number", onTypeNumber)
            )
        }
    }

    private func barcodeMessage(_ text: Text, primary: (LocalizedStringResource, () -> Void), secondary: (LocalizedStringResource, () -> Void)) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.md) {
            text
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: primary.1) { Text(primary.0) }
                .buttonStyle(.vessPrimary)
            Button(action: secondary.1) { Text(secondary.0) }
                .buttonStyle(.vessSecondary)
        }
    }

    /// Each mode's lines: what happens to the photo and what's left today,
    /// or, for barcodes, where the data comes from.
    private var footer: some View {
        VStack(alignment: .leading, spacing: VESSSpacing.xxs) {
            switch mode {
            case .barcode:
                Text("Product data from Open Food Facts")
                    .foregroundStyle(VESSColor.secondaryText)
            case .meal, .menu:
                if mode == .menu, let menu {
                    Button {
                        showMenu = true
                    } label: {
                        Text("Back to \(menu.title?.isEmpty == false ? menu.title ?? "" : String(localized: "the menu"))")
                            .vessTextStyle(.bodyS)
                            .foregroundStyle(VESSColor.accent)
                            .frame(minHeight: VESSHitTarget.minimum)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("photo.menuAgain")
                }
                Text(mode == .menu ? "Reads the dishes, estimates each one. The photo is then deleted." : "Used only for this estimate, then deleted.")
                    .foregroundStyle(VESSColor.secondaryText)
                Text(quotaLine)
                    .foregroundStyle(VESSColor.tertiaryText)
            }
        }
        .vessTextStyle(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VESSSpacing.screenInset)
        .padding(.top, VESSSpacing.sm)
        .padding(.bottom, VESSSpacing.xs)
        .background(VESSColor.background)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("photo.footer")
    }

    /// "Uses 1 photo estimate · 9 left today · resets 1:00"; without the
    /// count until it's known.
    private var quotaLine: String {
        let resets = AIQuotaText.resetsShort(after: AppClock.now)
        let left = remainingToday.map { String(localized: "\($0) left today") }
        let parts = (mode == .menu ? [String(localized: "Uses 1 photo estimate")] : []) + [left].compactMap { $0 } + [resets]
        return parts.joined(separator: " · ")
    }

    private var looking: some View {
        VStack(spacing: VESSSpacing.lg) {
            RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                .fill(VESSColor.fill)
                .overlay {
                    if let lookingImage {
                        Image(uiImage: lookingImage)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous).strokeBorder(VESSColor.borderStrong, lineWidth: 2))
                .aspectRatio(1, contentMode: .fit)
                .phaseAnimator(reduceMotion ? [1.0] : [0.4, 1.0]) { frame, opacity in
                    frame.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 1.2) }
                .accessibilityHidden(true)
            Text(mode == .menu ? "Reading the menu…" : "Looking at your photo…")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.secondaryText)
                .accessibilityIdentifier("photo.looking")
        }
        .padding(.horizontal, VESSSpacing.screenInset)
        .vessContentTop(VESSSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func emptyResult(_ note: String?) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            Text(mode == .menu ? "No dishes found. Try another photo with the whole page in the frame." : "No food found. Try another photo or search instead.")
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("photo.empty")
            Button("Try another photo") { phase = .camera }
                .buttonStyle(.vessPrimary)
            Button("Search instead", action: onSearchInstead)
                .buttonStyle(.vessSecondary)
        }
        .padding(.horizontal, VESSSpacing.screenInset)
        .vessContentTop(VESSSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func failed(_ error: BackendError) -> some View {
        VStack(alignment: .leading, spacing: VESSSpacing.lg) {
            Text(error == .dailyLimit ? "That's today's free photo estimates. Back tomorrow." : error.message)
                .vessTextStyle(.bodyM)
                .foregroundStyle(VESSColor.warningText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("photo.failure")
            if error == .notSignedIn {
                Button("Sign in") { showSignIn = true }
                    .buttonStyle(.vessPrimary)
            } else if error != .dailyLimit, error != .notConfigured {
                // The photo is already gone; a new one is taken for a retry.
                Button("Take another photo") { phase = .camera }
                    .buttonStyle(.vessPrimary)
            }
            Button("Search instead", action: onSearchInstead)
                .buttonStyle(.vessSecondary)
        }
        .padding(.horizontal, VESSSpacing.screenInset)
        .vessContentTop(VESSSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Actions

    private var remainingToday: Int? {
        remaining >= 0 && remainingDay == CoachView.serverDay(AppClock.now) ? remaining : nil
    }

    private func shoot() {
        Task {
            if let data = await camera.capture() { use(data) } else { showError = true }
        }
    }

    /// Asks for consent once; then sends.
    private func use(_ data: Data) {
        guard consent.isGranted(.photo) else {
            pendingPhoto = data
            showConsent = true
            return
        }
        send(data)
    }

    private func send(_ photo: Data) {
        pendingPhoto = nil
        camera.stop()
        phase = .looking
        let meal = meal
        Task {
            let jpeg = await Task.detached(priority: .userInitiated) { PhotoPreparation.jpeg(from: photo) }.value
            guard let jpeg else {
                phase = .failed(.badRequest("bad_image"))
                return
            }
            lookingImage = UIImage(data: jpeg)
            defer { lookingImage = nil }
            do {
                if mode == .menu {
                    let response: MenuScanResponse = try await account.callFunction(
                        "menu", body: MenuScanRequest(jpeg: jpeg, locale: CoachRequest.locale)
                    )
                    if let left = response.remaining { setRemaining(left) }
                    let dishes = MenuRules.dishes(from: response)
                    let note = response.note?.isEmpty == false ? response.note : nil
                    if dishes.isEmpty {
                        phase = .empty(note)
                    } else {
                        let title = response.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                        menu = MenuScanResult(title: title?.isEmpty == false ? title : nil, dishes: dishes, note: note)
                        phase = .camera
                        showMenu = true
                    }
                    return
                }
                let response: PhotoEstimateResponse = try await account.callFunction(
                    "food-photo", body: FoodPhotoRequest(jpeg: jpeg, meal: meal, locale: CoachRequest.locale)
                )
                if let left = response.remaining { setRemaining(left) }
                items = PhotoEstimateRules.items(from: response)
                note = response.note?.isEmpty == false ? response.note : nil
                phase = items.isEmpty ? .empty(note) : .review
            } catch {
                let backend = BackendError.from(error)
                if backend == .dailyLimit { setRemaining(0) }
                phase = .failed(backend)
            }
            // `photo` and `jpeg` go out of scope here: nothing is kept.
        }
    }

    private func setRemaining(_ value: Int) {
        remaining = value
        remainingDay = CoachView.serverDay(AppClock.now)
    }

    private func save() {
        guard !isSaved, let profile = store.profile else { return }
        let entries = PhotoEstimateRules.entries(items, userID: profile.id, meal: meal, at: meal.logTime(on: day, calendar: .current))
        guard !entries.isEmpty else { return }
        isSaved = true
        do {
            for entry in entries { try store.add(entry) }
            undo.show(Text("Added to \(Text(meal.title)) · Estimated")) { store in
                for entry in entries { try store.deleteFoodEntry(id: entry.id) }
            }
            onLogged()
        } catch {
            isSaved = false
            showError = true
        }
    }

    // MARK: Barcode

    /// Detection runs only in Barcode mode, while nothing else is showing.
    private func updateDetection() {
        camera.detectsBarcodes = mode == .barcode && scan == .scanning && found == nil
    }

    private func resumeScanning() {
        scan = .scanning
        updateDetection()
    }

    private func detected(_ code: String) {
        guard mode == .barcode, scan == .scanning, !code.isEmpty else { return }
        scan = .reading(code)
        updateDetection()
        haptics.play(.success)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { flash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) { flash = false }
        }
        Task {
            #if DEBUG
            // `-demoBarcode`: the simulator has no camera or network.
            if ProcessInfo.processInfo.arguments.contains("-demoBarcode"), code == MockData.barcodeDemo.barcode {
                try? await Task.sleep(for: .seconds(1))
                scan = .scanning
                found = MockData.barcodeDemo
                updateDetection()
                return
            }
            #endif
            switch await lookup.lookUp(barcode: code) {
            case .success(let food):
                scan = .scanning
                found = food
                updateDetection()
            case .failure(.notFound):
                scan = .notFound(code)
            case .failure(let error):
                scan = .failed(code, error)
            }
        }
    }

    /// The library button in Barcode mode: read the code in a photo.
    private func readBarcode(inPhoto data: Data) async {
        if let code = await PhotoBarcodeReader.code(in: data) {
            scan = .scanning
            detected(code)
        } else {
            scan = .noCodeInPhoto
            updateDetection()
        }
    }

    /// What's left today, from the server when this device doesn't know yet.
    private func loadRemaining() async {
        guard account.isSignedIn, remainingToday == nil,
              let left = try? await account.remainingToday(kind: "photo") else { return }
        setRemaining(left)
    }

    #if DEBUG
    /// A plain plate-coloured image for `-aiMock` captures (no camera in the simulator).
    static func samplePhoto() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200))
        let image = renderer.image { context in
            UIColor(white: 0.85, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
            UIColor(white: 0.97, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 300, y: 100, width: 1000, height: 1000))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
    #endif
}

/// I05–I07: every item editable before saving. Nothing is logged until Save.
struct PhotoReviewView: View {
    @Binding var items: [EstimatedItem]
    @Binding var meal: MealType
    let note: String?
    let day: Date
    let onSave: () -> Void

    var body: some View {
        let total = PhotoEstimateRules.total(items)
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                Menu {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.dayOrder) { meal in
                            Text(meal.title).tag(meal)
                        }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                        Text(meal.toTitle).vessTextStyle(.titleL)
                        Image(systemName: "chevron.down")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(VESSColor.secondaryText)
                    }
                    .foregroundStyle(VESSColor.text)
                    .frame(minHeight: VESSHitTarget.minimum)
                }
                .accessibilityLabel(Text("Meal: \(Text(meal.title))"))
                .accessibilityIdentifier("photo.meal")

                Text("^[\(items.count) item](inflect: true) estimated. Check each one; nothing is logged until you add it.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let note {
                    Text(verbatim: note)
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.warningText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: VESSSpacing.sm) {
                    ForEach($items) { $item in
                        EstimatedItemRow(item: $item) {
                            items.removeAll { $0.id == item.id }
                        }
                    }
                }

                Button("Add item") {
                    items.append(EstimatedItem(name: "", amount: 100, isMilliliters: false,
                                               perUnit: NutritionFacts(calories: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0),
                                               confidence: .high, isManual: true))
                }
                .buttonStyle(.vessSecondary)
                .accessibilityIdentifier("photo.addItem")

                HStack(alignment: .firstTextBaseline, spacing: VESSSpacing.xs) {
                    Text("≈\u{00A0}\(VESSFormat.calories(total.calories))")
                        .vessTextStyle(.displayM)
                        .foregroundStyle(VESSColor.text)
                    Text("kcal · Estimated")
                        .vessTextStyle(.bodyS)
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("photo.total")
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .vessKeyboardDoneButton()
        .vessBottomAction {
            Button(action: onSave) { Text(meal.addToTitle) }
                .buttonStyle(.vessPrimary)
                .disabled(PhotoEstimateRules.entries(items, userID: UUID(), meal: meal, at: day).isEmpty)
                .accessibilityIdentifier("photo.save")
        }
    }
}

/// One estimated item: name, amount stepper, kcal and macros, confidence,
/// delete. Low confidence is framed and labelled "Check this".
private struct EstimatedItemRow: View {
    @Binding var item: EstimatedItem
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var kcalText = ""

    /// Items added by hand: kcal typed, not an estimate.
    private var isManual: Bool { item.isManual }

    var body: some View {
        let nutrition = item.nutrition
        let shape = RoundedRectangle(cornerRadius: VESSRadius.control, style: .continuous)
        VStack(alignment: .leading, spacing: VESSSpacing.sm) {
            HStack(alignment: .top, spacing: VESSSpacing.sm) {
                TextField("Name", text: $item.name, prompt: Text("What is it?").foregroundStyle(VESSColor.tertiaryText), axis: .vertical)
                    .vessTextStyle(.bodyMStrong)
                    .foregroundStyle(VESSColor.text)
                    .padding(.top, VESSSpacing.sm)
                    .accessibilityLabel("Name")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(VESSColor.secondaryText)
                }
                .buttonStyle(.plain)
                .frame(minWidth: VESSHitTarget.minimum, minHeight: VESSHitTarget.minimum)
                .contentShape(Rectangle())
                .accessibilityLabel(item.name.isEmpty ? Text("Remove item") : Text("Remove \(item.name)"))
            }

            if !isManual {
                HStack(spacing: VESSSpacing.xs) {
                    VessTagLabel(text: "Estimated", warning: false)
                    if item.needsCheck { VessTagLabel(text: "Check this", warning: true) }
                }
            }

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: VESSSpacing.sm))
                : AnyLayout(HStackLayout(alignment: .center, spacing: VESSSpacing.sm))
            layout {
                HStack(spacing: VESSSpacing.sm) {
                    VESSIconButton(systemImage: "minus", label: "Less") { item.amount = PhotoEstimateRules.stepped(item.amount, by: -1) }
                        .disabled(item.amount <= EstimatedItem.step)
                    Text("\(VESSFormat.quantity(item.amount)) \(item.isMilliliters ? "ml" : "g")")
                        .vessTextStyle(.numberS)
                        .monospacedDigit()
                        .foregroundStyle(VESSColor.text)
                        .frame(minWidth: 64)
                        .accessibilityLabel(Text("Amount \(VESSFormat.quantity(item.amount)) \(item.isMilliliters ? "millilitres" : "grams")"))
                    VESSIconButton(systemImage: "plus", label: "More") { item.amount = PhotoEstimateRules.stepped(item.amount, by: 1) }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if isManual {
                    VESSTextField("Energy", text: $kcalText, unit: "kcal", titleInside: true)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 140)
                        .onChange(of: kcalText) { _, text in
                            let kcal = VESSFormat.number(from: text) ?? 0
                            item.perUnit = NutritionFacts(calories: kcal / max(item.amount, 1), proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
                        }
                } else {
                    Text("\(VESSFormat.calories(nutrition.calories))\u{00A0}kcal")
                        .vessTextStyle(.numberS)
                        .foregroundStyle(VESSColor.text)
                }
            }

            if !isManual {
                Text("\(VESSFormat.grams(nutrition.proteinGrams))\u{00A0}g protein · \(VESSFormat.grams(nutrition.carbohydrateGrams))\u{00A0}g carbs · \(VESSFormat.grams(nutrition.fatGrams))\u{00A0}g fat")
                    .vessTextStyle(.bodyS)
                    .foregroundStyle(VESSColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(VESSSpacing.md)
        .background(VESSColor.fill, in: shape)
        .overlay(shape.strokeBorder(item.needsCheck ? VESSColor.warning : VESSColor.divider, lineWidth: item.needsCheck ? 1.5 : 1))
        .accessibilityElement(children: .contain)
    }
}

/// A small tag: "Estimated", or amber "Check this".
private struct VessTagLabel: View {
    let text: LocalizedStringResource
    let warning: Bool

    var body: some View {
        Text(text)
            .vessTextStyle(.labelCapsS)
            .foregroundStyle(warning ? VESSColor.warningText : VESSColor.secondaryText)
            .padding(.horizontal, VESSSpacing.xs)
            .padding(.vertical, VESSSpacing.xxs)
            .background(warning ? VESSColor.warningTint : VESSColor.background, in: Capsule())
    }
}

/// Barcode mode's guide: four corner marks around a wide, short window and
/// a thin line across it. Still: nothing moves, with or without Reduce Motion.
private struct BarcodeGuide: View {
    private static let corner: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.78
            let height = min(proxy.size.height * 0.34, width * 0.55)
            let rect = CGRect(x: (proxy.size.width - width) / 2, y: (proxy.size.height - height) / 2, width: width, height: height)
            ZStack {
                Path { path in
                    let c = Self.corner
                    // Top left, top right, bottom right, bottom left.
                    path.move(to: CGPoint(x: rect.minX, y: rect.minY + c)); path.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))
                    path.move(to: CGPoint(x: rect.maxX - c, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
                    path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - c)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
                    path.move(to: CGPoint(x: rect.minX + c, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
                }
                .stroke(VESSColor.text, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                Rectangle()
                    .fill(VESSColor.text.opacity(0.6))
                    .frame(width: width - 2 * Self.corner, height: 1)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
