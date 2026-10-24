import PhotosUI
import SwiftUI
import UIKit

/// Photo in the Add sheet (I02–I08): take or pick a photo, send it once for
/// an estimate, then review every item before anything is logged. The photo
/// is made smaller, stripped of metadata, and dropped once the answer is in.
struct AddPhotoContent: View {
    let day: Date
    @Binding var meal: MealType
    let onSearchInstead: () -> Void
    let onLogged: () -> Void

    @Environment(AccountStore.self) private var account
    @Environment(AIConsentStore.self) private var consent
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("photo.remaining") private var remaining = -1
    @AppStorage("photo.remainingDay") private var remainingDay = ""

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

    var body: some View {
        Group {
            if !account.isSignedIn {
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
                if let data = try? await item.loadTransferable(type: Data.self) { use(data) }
                pickerItem = nil
            }
        }
        .vessErrorAlert(isPresented: $showError)
        .onDisappear { camera.stop() }
    }

    // MARK: States

    private var signedOut: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                Text("Photo estimates need an account. Only for Coach, photo estimates and AI Chef; your log stays on this iPhone.")
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

    private var cameraView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.lg) {
                Text("Fit the whole plate in the frame.")
                    .vessTextStyle(.bodyM)
                    .foregroundStyle(VESSColor.secondaryText)

                ZStack {
                    RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous)
                        .fill(VESSColor.fill)
                    switch camera.state {
                    case .running:
                        CameraPreview(session: camera.box.session)
                            .clipShape(RoundedRectangle(cornerRadius: VESSRadius.large, style: .continuous))
                    case .idle:
                        ProgressView()
                    case .unavailable, .denied:
                        VStack(spacing: VESSSpacing.sm) {
                            Image(systemName: "camera")
                                .font(.title2)
                                .foregroundStyle(VESSColor.secondaryText)
                                .accessibilityHidden(true)
                            Text(camera.state == .denied ? "Camera access is off for VESS. Pick a photo, or turn it on in Settings." : "The camera isn't available here. Pick a photo instead.")
                                .vessTextStyle(.bodyS)
                                .foregroundStyle(VESSColor.secondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(VESSSpacing.lg)
                    }
                }
                // Square, so the shutter stays on screen.
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        Label("Photos", systemImage: "photo.on.rectangle")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .foregroundStyle(VESSColor.text)
                            .frame(width: VESSSize.addButton, height: VESSSize.addButton)
                            .background(VESSColor.fill, in: Circle())
                    }
                    .accessibilityLabel("Pick a photo")
                    .accessibilityIdentifier("photo.pick")
                    Spacer()
                    Button(action: shoot) {
                        Circle()
                            .fill(VESSColor.accentFill)
                            .frame(width: 72, height: 72)
                            .overlay(Circle().strokeBorder(VESSColor.borderStrong, lineWidth: 4).padding(-6))
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.state != .running)
                    .opacity(camera.state == .running ? 1 : 0.4)
                    .accessibilityLabel("Take photo")
                    .accessibilityIdentifier("photo.shutter")
                    Spacer()
                    Button { camera.isFlashOn.toggle() } label: {
                        Image(systemName: camera.isFlashOn ? "bolt.fill" : "bolt.slash")
                            .font(.title3)
                            .foregroundStyle(VESSColor.text)
                            .frame(width: VESSSize.addButton, height: VESSSize.addButton)
                            .background(VESSColor.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(camera.hasFlash ? 1 : 0)
                    .disabled(!camera.hasFlash)
                    .accessibilityLabel(camera.isFlashOn ? "Flash on" : "Flash off")
                }

                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-aiMock") {
                    Button("Use a sample photo (debug)") { use(Self.samplePhoto()) }
                        .buttonStyle(.vessSecondary)
                        .accessibilityIdentifier("photo.sample")
                }
                #endif

                Group {
                    if let left = remainingToday {
                        Text("The photo is used only to estimate this meal, then dropped. · ^[\(left) estimate](inflect: true) left today · \(AIQuotaText.resets(after: AppClock.now))")
                    } else {
                        Text("The photo is used only to estimate this meal, then dropped.")
                    }
                }
                .vessTextStyle(.caption)
                .foregroundStyle(VESSColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .vessContentTop(VESSSpacing.md)
            .padding(.bottom, VESSSpacing.xl)
        }
        .task { await camera.start() }
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
            Text("Looking at your photo…")
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
            Text("No food found. Try another photo or search instead.")
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
                    Text("≈ \(VESSFormat.calories(total.calories))")
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
                    Text("\(VESSFormat.calories(nutrition.calories)) kcal")
                        .vessTextStyle(.numberS)
                        .foregroundStyle(VESSColor.text)
                }
            }

            if !isManual {
                Text("\(VESSFormat.grams(nutrition.proteinGrams)) g protein · \(VESSFormat.grams(nutrition.carbohydrateGrams)) g carbs · \(VESSFormat.grams(nutrition.fatGrams)) g fat")
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
