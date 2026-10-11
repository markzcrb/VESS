import SwiftUI

/// Look up a packaged product by the number printed under its barcode.
/// Camera scanning is planned; it needs camera permission, which is added
/// only after the permission text is approved.
struct BarcodeLookupView: View {
    @Environment(FoodLookupService.self) private var lookup

    let onFound: (Food) -> Void

    @State private var code = ""
    @State private var isLooking = false
    @State private var message: LocalizedStringResource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VESSSpacing.xl) {
                VStack(alignment: .leading, spacing: VESSSpacing.xs) {
                    Text("Enter a barcode")
                        .vessTextStyle(.detailTitle)
                    Text("Type the number printed under the barcode. Products you've looked up before also work offline.")
                        .vessTextStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VESSTextField("Barcode", text: $code, prompt: Text("8 to 14 digits"))
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("barcode.code")

                if isLooking {
                    HStack(spacing: VESSSpacing.sm) {
                        ProgressView()
                        Text("Looking up on \(lookup.providerName)…")
                            .vessTextStyle(.secondary)
                    }
                } else if let message {
                    Text(message)
                        .vessTextStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("barcode.message")
                }
            }
            .padding(.horizontal, VESSSpacing.screenInset)
            .padding(.bottom, VESSSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(VESSColor.card)
        .vessBottomAction {
            Button("Look up") { Task { await lookUp() } }
                .buttonStyle(.vessPrimary)
                .disabled(!isValid || isLooking)
                .accessibilityIdentifier("barcode.lookUp")
        }
        .navigationBarTitleDisplayMode(.inline)
        .vessKeyboardDoneButton()
    }

    private var isValid: Bool {
        let digits = code.filter(\.isNumber)
        return digits.count == code.count && (8...14).contains(digits.count)
    }

    private func lookUp() async {
        isLooking = true
        message = nil
        let result = await lookup.lookUp(barcode: code)
        isLooking = false
        switch result {
        case .success(let food):
            onFound(food)
        case .failure(let error):
            message = Self.message(for: error)
        }
    }

    static func message(for error: FoodProviderError) -> LocalizedStringResource {
        switch error {
        case .notFound: "No product with this barcode on Open Food Facts. You can create it as your own food."
        case .offline: "You're offline, and this product isn't saved on this iPhone yet."
        case .rateLimited: "Too many lookups in a short time. Try again in a minute."
        case .invalidBarcode: "That doesn't look like a barcode. Check the digits."
        case .timedOut, .server, .invalidResponse: "Open Food Facts didn't respond. Try again later."
        }
    }
}
