import SwiftUI

/// The last batch of foods logged from the Add sheet, so the screen that
/// opened the sheet can offer Undo for a few seconds after it closes.
@Observable
final class FoodLogUndo {
    private(set) var entries: [FoodLogEntry] = []
    private(set) var meal: MealType?
    private var dismissal: Task<Void, Never>?

    /// Offers Undo for `entries` for five seconds.
    func show(_ entries: [FoodLogEntry], meal: MealType) {
        dismissal?.cancel()
        self.entries = entries
        self.meal = meal
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    /// Deletes the batch from the store.
    func undo(in store: LocalStore) throws {
        let batch = entries
        clear()
        for entry in batch {
            try store.deleteFoodEntry(id: entry.id)
        }
    }

    private func clear() {
        dismissal?.cancel()
        entries = []
        meal = nil
    }
}

extension View {
    /// Shows "Added N items to Dinner · Undo" above the bottom edge after a
    /// batch is logged from the Add sheet.
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
                if let meal = undo.meal, !undo.entries.isEmpty {
                    VESSUndoToast(message: Text("Added ^[\(undo.entries.count) item](inflect: true) to \(Text(meal.title))")) {
                        do { try undo.undo(in: store) } catch { showError = true }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: undo.entries.count)
            .vessErrorAlert(isPresented: $showError)
    }
}
