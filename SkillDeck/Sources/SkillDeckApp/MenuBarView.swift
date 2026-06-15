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
                ForEach(favs) { item in
                    Button(item.name) { fire(item) }
                }
            }
        }
        if !recents.isEmpty {
            Section("Recent") {
                ForEach(recents) { item in
                    Button(item.name) { fire(item) }
                }
            }
        }
        Divider()
        Button("Open SkillDeck") { openWindow(id: "main") }
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private func fire(_ item: SkillItem) {
        let ok = Injector.inject(store.effectiveInsertText(for: item.id), into: tracker.previousApp)
        store.recordUse(item.id)
        if !ok { Injector.requestAccessibility() }
    }
}
