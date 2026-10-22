import SwiftUI

/// The last thing logged (foods from the Add sheet, a drink, a workout), so
/// the screen behind can offer Undo for five seconds after the sheet or
/// push closes (MOTION.md: logging).
@Observable
final class FoodLogUndo {
    struct Item: Identifiable {
        let id = UUID()
        let message: Text
        let undo: (LocalStore) throws -> Void
    }

    private(set) var item: Item?
    /// Counts every log, so the light haptic fires each time.
    private(set) var loggedCount = 0
    private var dismissal: Task<Void, Never>?

    /// "Added 2 items to Dinner", undone by deleting the entries.
    func show(_ entries: [FoodLogEntry], meal: MealType) {
        show(Text("Added ^[\(entries.count) item](inflect: true) to \(Text(meal.title))")) { store in
            for entry in entries {
                try store.deleteFoodEntry(id: entry.id)
            }
        }
    }

    /// Offers Undo for five seconds.
    func show(_ message: Text, undo: @escaping (LocalStore) throws -> Void) {
        dismissal?.cancel()
        item = Item(message: message, undo: undo)
        loggedCount += 1
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    /// Reverses the last log.
    func undo(in store: LocalStore) throws {
        guard let item else { return }
        clear()
        try item.undo(store)
    }

    private func clear() {
        dismissal?.cancel()
        item = nil
    }
}

extension View {
    /// Shows "Added 2 items to Dinner · Undo" above the bottom edge after
    /// something is logged.
    func vessFoodUndoToast() -> some View {
        modifier(FoodUndoToastModifier())
    }
}

private struct FoodUndoToastModifier: ViewModifier {
    @Environment(LocalStore.self) private var store
    @Environment(FoodLogUndo.self) private var undo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showError = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let item = undo.item {
                    VESSUndoToast(message: item.message) {
                        do { try undo.undo(in: store) } catch { showError = true }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? VESSMotion.reducedCrossfade : VESSMotion.toast, value: undo.item?.id)
            .vessErrorAlert(isPresented: $showError)
    }
}
