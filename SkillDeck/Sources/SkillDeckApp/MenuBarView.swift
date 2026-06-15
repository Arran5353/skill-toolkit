import SwiftUI
import AppKit
import SkillDeckCore

struct MenuBarView: View {
    let store: AppStore
    let tracker: FrontmostAppTracker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let favs = store.favoriteItems()
        let recents = store.recentItems(limit: 5)

        if !favs.isEmpty {
            Section("Favorites") {
                ForEach(favs) { node in
                    Button(node.name) { fire(node) }
                }
            }
        }
        if !recents.isEmpty {
            Section("Recent") {
                ForEach(recents) { node in
                    Button(node.name) { fire(node) }
                }
            }
        }
        Divider()
        Button("Open SkillDeck") { openWindow(id: "main") }
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private func fire(_ node: Node) {
        let ok = Injector.inject(store.effectiveInsertText(for: node.id), into: tracker.previousApp)
        store.recordUse(node.id)
        if !ok { Injector.requestAccessibility() }
    }
}
