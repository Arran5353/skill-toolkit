import SwiftUI
import AppKit
import SkillDeckCore

struct DetailView: View {
    let store: AppStore
    let tracker: FrontmostAppTracker
    @Binding var selection: String?
    @State private var editedInsert: String = ""
    @State private var showCopyOnlyNote = false

    private var item: SkillItem? { selection.flatMap { store.item(id: $0) } }

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.name).font(.title.bold())
                    Text(scopeLabel(item)).font(.caption).foregroundStyle(.secondary)
                    if !item.description.isEmpty {
                        Text(item.description)
                    }
                    Divider()
                    Text("Insert text").font(.headline)
                    TextField("insert text", text: $editedInsert, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { store.setOverride(item.id, text: editedInsert) }

                    HStack {
                        Button {
                            inject(item)
                        } label: { Label("Inject into terminal", systemImage: "arrow.down.doc") }
                            .buttonStyle(.borderedProminent)
                        Button {
                            copyOnly(item)
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                        Button {
                            store.toggleFavorite(item.id)
                        } label: {
                            Label(store.isFavorite(item.id) ? "Unfavorite" : "Favorite",
                                  systemImage: store.isFavorite(item.id) ? "star.fill" : "star")
                        }
                    }
                    if showCopyOnlyNote {
                        Text("Accessibility not granted — copied to clipboard. Paste with Cmd+V.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if !item.body.isEmpty {
                        Divider()
                        Text("Usage").font(.headline)
                        Text(item.body).font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: selection) { _, _ in
                editedInsert = store.effectiveInsertText(for: item.id)
                showCopyOnlyNote = false
            }
            .onAppear { editedInsert = store.effectiveInsertText(for: item.id) }
        } else {
            ContentUnavailableView("Select an item",
                systemImage: "sidebar.left",
                description: Text("Pick a skill or command to see its usage and inject it."))
        }
    }

    private func inject(_ item: SkillItem) {
        let text = store.effectiveInsertText(for: item.id)
        let ok = Injector.inject(text, into: tracker.previousApp)
        store.recordUse(item.id)
        if !ok {
            Injector.requestAccessibility()
            showCopyOnlyNote = true
        }
    }

    private func copyOnly(_ item: SkillItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(store.effectiveInsertText(for: item.id), forType: .string)
        store.recordUse(item.id)
    }

    private func scopeLabel(_ item: SkillItem) -> String {
        let kind = item.kind == .skill ? "skill" : "command"
        let where_: String
        switch item.scope {
        case .user: where_ = item.pluginName.map { "plugin: \($0)" } ?? "user"
        case .project(let n): where_ = "project: \(n)"
        case .builtin: where_ = "built-in"
        }
        return "\(kind) - \(where_)"
    }
}
