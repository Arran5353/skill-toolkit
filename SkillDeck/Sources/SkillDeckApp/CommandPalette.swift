import SwiftUI
import AppKit
import SkillDeckCore

struct CommandPalette: View {
    let store: AppStore
    let tracker: FrontmostAppTracker
    let onClose: () -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var searchFocused: Bool
    @State private var showCopyOnlyNote = false
    @StateObject private var coordinator = InjectCoordinator()

    private var results: [Node] {
        store.fuzzySearch(query, limit: 12)
    }

    var body: some View {
        ZStack {
            // Dim backdrop — click to dismiss
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            // Centered card
            VStack(spacing: 0) {
                searchField
                Divider()
                resultsList
                if showCopyOnlyNote {
                    copyNote
                }
            }
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.30), radius: 30, y: 10)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            searchFocused = true
            selectedIndex = 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            showCopyOnlyNote = false
        }
        // Key handling — attach to the outer ZStack so it captures events even when list is active
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, max(results.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            runSelected()
            return .handled
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .sheet(item: $coordinator.pending) { fill in
            ParameterFillSheet(
                pending: fill,
                onInject: { values in
                    coordinator.complete(values: values, store: store, tracker: tracker)
                    onClose()
                },
                onCancel: { coordinator.cancel() }
            )
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search skills & commands  (⌥⌘K from any app)", text: $query)
                .textFieldStyle(.plain)
                .font(.system(.title3, design: .rounded))
                .focused($searchFocused)
                .submitLabel(.go)
                .onSubmit { runSelected() }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Results list

    private var resultsList: some View {
        Group {
            if results.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { idx, node in
                                PaletteRow(
                                    node: node,
                                    insertText: store.effectiveInsertText(for: node.id),
                                    isSelected: idx == selectedIndex
                                )
                                .id(idx)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = idx
                                    runSelected()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selectedIndex) { _, newIdx in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(newIdx, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("No results for \"\(query)\"")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var copyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Accessibility not granted — copied to clipboard. Paste with ⌘V.")
                .font(.callout)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Inject

    private func runSelected() {
        guard !results.isEmpty else { return }
        let clamped = min(selectedIndex, results.count - 1)
        let node = results[clamped]
        coordinator.begin(node: node, store: store, tracker: tracker) { ok in
            if ok {
                onClose()
            } else {
                Injector.requestAccessibility()
                showCopyOnlyNote = true
                // Stay open to show the copy-only note (mirror DetailView behavior)
            }
        }
    }
}

// MARK: - PaletteRow

private struct PaletteRow: View {
    let node: Node
    let insertText: String
    let isSelected: Bool

    var body: some View {
        let accent = NodeTheme.accent(node.kind)
        HStack(spacing: 12) {
            // Kind icon
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(accent.opacity(isSelected ? 0.25 : 0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: NodeTheme.icon(node.kind))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }

            // Name + description
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(isSelected ? accent : .primary)
                    .lineLimit(1)
                if !node.description.isEmpty {
                    Text(node.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Effective insert text (monospaced, dimmed)
            Text(insertText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
    }
}
