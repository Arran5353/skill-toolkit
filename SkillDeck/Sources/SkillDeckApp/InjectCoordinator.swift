import SwiftUI
import SkillDeckCore

@MainActor
final class InjectCoordinator: ObservableObject {
    @Published var pending: PendingFill?

    struct PendingFill: Identifiable {
        let id = UUID()
        let node: Node
        let template: String
        let placeholders: [ArgumentPlaceholders.Placeholder]
        /// Called with inject success when the user completes the form.
        let completion: (Bool) -> Void
    }

    /// If template has placeholders, set `pending` (UI shows a sheet) and call completion later.
    /// If no placeholders, inject immediately and call completion with the result.
    func begin(node: Node, store: AppStore, tracker: FrontmostAppTracker, completion: @escaping (Bool) -> Void) {
        let template = store.effectiveInsertText(for: node.id)
        let ph = ArgumentPlaceholders.placeholders(in: template)
        if ph.isEmpty {
            let ok = Self.doInject(template, node: node, store: store, tracker: tracker)
            completion(ok)
        } else {
            pending = PendingFill(node: node, template: template, placeholders: ph, completion: completion)
        }
    }

    func complete(values: [String: String], store: AppStore, tracker: FrontmostAppTracker) {
        guard let p = pending else { return }
        let filled = ArgumentPlaceholders.fill(p.template, values: values)
        let ok = Self.doInject(filled, node: p.node, store: store, tracker: tracker)
        pending = nil
        p.completion(ok)
    }

    func cancel() {
        pending = nil
    }

    @discardableResult
    static func doInject(_ text: String, node: Node, store: AppStore, tracker: FrontmostAppTracker) -> Bool {
        let ok = Injector.inject(text, into: tracker.previousApp)
        store.recordUse(node.id)
        return ok
    }
}
