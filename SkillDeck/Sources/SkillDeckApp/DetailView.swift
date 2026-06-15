import SwiftUI
import AppKit
import SkillDeckCore

struct DetailView: View {
    let store: AppStore
    let tracker: FrontmostAppTracker
    @Binding var selection: String?
    @State private var editedInsert: String = ""
    @State private var showCopyOnlyNote = false

    private var node: Node? { selection.flatMap { store.node(id: $0) } }

    var body: some View {
        if let node {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(node.name).font(.title.bold())
                    Text(kindLabel(node)).font(.caption).foregroundStyle(.secondary)
                    if !node.description.isEmpty {
                        Text(node.description)
                    }
                    Divider()
                    Text("Insert text").font(.headline)
                    TextField("insert text", text: $editedInsert, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { store.setOverride(node.id, text: editedInsert) }

                    HStack {
                        Button {
                            inject(node)
                        } label: { Label("Inject into terminal", systemImage: "arrow.down.doc") }
                            .buttonStyle(.borderedProminent)
                        Button {
                            copyOnly(node)
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                        if node.isLeaf {
                            Button {
                                store.toggleFavorite(node.id)
                            } label: {
                                Label(
                                    store.isFavorite(node.id) ? "Unfavorite" : "Favorite",
                                    systemImage: store.isFavorite(node.id) ? "star.fill" : "star"
                                )
                            }
                        }
                    }
                    if showCopyOnlyNote {
                        Text("Accessibility not granted — copied to clipboard. Paste with Cmd+V.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let body = node.body, !body.isEmpty {
                        Divider()
                        Text("Usage").font(.headline)
                        Text(body)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: selection) { _, _ in
                editedInsert = store.effectiveInsertText(for: node.id)
                showCopyOnlyNote = false
            }
            .onAppear { editedInsert = store.effectiveInsertText(for: node.id) }
        } else {
            ContentUnavailableView(
                "Select an item",
                systemImage: "sidebar.left",
                description: Text("Pick a skill or command to see its usage and inject it."))
        }
    }

    private func inject(_ node: Node) {
        let text = store.effectiveInsertText(for: node.id)
        let ok = Injector.inject(text, into: tracker.previousApp)
        store.recordUse(node.id)
        if !ok {
            Injector.requestAccessibility()
            showCopyOnlyNote = true
        }
    }

    private func copyOnly(_ node: Node) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(store.effectiveInsertText(for: node.id), forType: .string)
        store.recordUse(node.id)
    }

    private func kindLabel(_ node: Node) -> String {
        switch node.kind {
        case .skill:         return "skill"
        case .command:       return "command"
        case .builtinCommand: return "built-in command"
        case .localSkill:    return "local skill"
        case .plugin:        return "plugin"
        case .marketplace:   return "marketplace"
        }
    }
}
