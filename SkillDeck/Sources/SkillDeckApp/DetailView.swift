import SwiftUI
import AppKit
import SkillDeckCore

struct DetailView: View {
    let store: AppStore
    let tracker: FrontmostAppTracker
    @Binding var selection: String?
    @State private var editedInsert: String = ""
    @State private var showCopyOnlyNote = false
    @StateObject private var coordinator = InjectCoordinator()

    private var node: Node? { selection.flatMap { store.node(id: $0) } }

    var body: some View {
        if let node {
            let accent = NodeTheme.accent(node.kind)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(node, accent: accent)
                    insertCard(node, accent: accent)
                    if showCopyOnlyNote { copyOnlyNote }
                    if let body = node.body, !body.isEmpty {
                        SectionCard(title: "Usage", systemImage: "book.fill", accent: accent) {
                            MarkdownText(body, accent: accent)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accentBackdrop(accent)
            .onChange(of: selection) { _, newSel in
                editedInsert = store.effectiveInsertText(for: newSel ?? "")
                showCopyOnlyNote = false
            }
            .onAppear { editedInsert = store.effectiveInsertText(for: node.id) }
            .sheet(item: $coordinator.pending) { fill in
                ParameterFillSheet(
                    pending: fill,
                    onInject: { values in
                        coordinator.complete(values: values, store: store, tracker: tracker)
                    },
                    onCancel: { coordinator.cancel() }
                )
            }
        } else {
            emptyState
        }
    }

    // MARK: - Header

    private func header(_ node: Node, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            NodeIconTile(kind: node.kind)
            VStack(alignment: .leading, spacing: 6) {
                Text(node.name)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    KindBadge(kind: node.kind)
                    if let plugin = pluginContext(node) {
                        Label(plugin, systemImage: "puzzlepiece.extension")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if node.isLeaf { favoriteButton(node, accent: accent) }
        }
    }

    private func favoriteButton(_ node: Node, accent: Color) -> some View {
        let on = store.isFavorite(node.id)
        return Button {
            store.toggleFavorite(node.id)
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? Color.yellow : Color.secondary)
                .padding(8)
                .background(.background.secondary, in: Circle())
        }
        .buttonStyle(.plain)
        .help(on ? "Remove from favorites" : "Add to favorites")
    }

    // MARK: - Insert card

    private func insertCard(_ node: Node, accent: Color) -> some View {
        SectionCard(title: "Invocation", systemImage: "arrow.down.left.circle.fill", accent: accent) {
            if !node.description.isEmpty {
                Text(node.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
            }
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                TextField("insert text", text: $editedInsert, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { store.setOverride(node.id, text: editedInsert) }
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent.opacity(0.25), lineWidth: 1)
            )

            HStack(spacing: 10) {
                Button {
                    inject(node)
                } label: {
                    Label("Inject into terminal", systemImage: "arrow.down.doc.fill")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .controlSize(.large)

                Button {
                    copyOnly(node)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(.body, design: .rounded).weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 4)
        }
    }

    private var copyOnlyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Accessibility not granted — copied to clipboard. Paste with ⌘V.")
                .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Select an item", systemImage: "sparkles.rectangle.stack")
        } description: {
            Text("Pick a skill or command to see its usage and inject it into your terminal.")
        }
    }

    private func pluginContext(_ node: Node) -> String? {
        guard let parentID = node.parentID,
              let parent = store.node(id: parentID),
              parent.kind == .plugin else { return nil }
        return parent.name
    }

    // MARK: - Actions

    private func inject(_ node: Node) {
        coordinator.begin(node: node, store: store, tracker: tracker) { ok in
            if !ok {
                Injector.requestAccessibility()
                showCopyOnlyNote = true
            }
        }
    }

    private func copyOnly(_ node: Node) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(store.effectiveInsertText(for: node.id), forType: .string)
        store.recordUse(node.id)
    }
}
