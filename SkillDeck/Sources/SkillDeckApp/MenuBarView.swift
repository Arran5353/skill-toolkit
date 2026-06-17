import SwiftUI
import AppKit
import SkillDeckCore

struct MenuBarView: View {
    let store: AppStore
    let tracker: FrontmostAppTracker
    var updateAvailable: UpdateChecker.Release?
    var onCheckForUpdates: () -> Void
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
        Divider()
        if let rel = updateAvailable, let url = URL(string: rel.url) {
            Button("🔼 Update available: \(rel.version)") {
                NSWorkspace.shared.open(url)
            }
        }
        Button("Check for Updates…") { onCheckForUpdates() }
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private func fire(_ node: Node) {
        let ok = Injector.inject(store.effectiveInsertText(for: node.id), into: tracker.previousApp)
        store.recordUse(node.id)
        if !ok { Injector.requestAccessibility() }
    }
}
