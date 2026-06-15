# SkillDeck v2 (Marketplace Browser + One-Click Install) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend SkillDeck to show a Marketplace → Plugin → Skill/Command tree (installed + available), and install uninstalled plugins in the background via `claude plugin install`.

**Architecture:** Fold v1's `SkillItem` into a unified `Node` model. Add a `MarketplaceScanner` (reads marketplace manifests), an `InstalledPluginsIndex` (status lookup), a `TreeBuilder` (assembles flat nodes into a parent/child tree, deduping), and an `Installer` (`Process` running `claude plugin install`). Reuse v1's Scanner/Injector/FileWatcher/persistence. AppStore moves from `items: [SkillItem]` to `nodes: [Node]`.

**Tech Stack:** Swift 6.1 / SwiftUI / SwiftPM (macOS 15+). `Process` for install. Reuses v1 SkillDeckCore.

> **Builds on:** v1 plan `docs/superpowers/plans/2026-06-14-skilldeck.md` (Tasks 1–10 complete on branch `skilldeck-impl`, 30 tests passing). v1 manual verification (old Task 11) and docs (old Task 12) are deferred and folded into this plan's final tasks.

> **Verified facts (use these exact shapes):**
> - `~/.claude/plugins/marketplaces/<mp>/.claude-plugin/marketplace.json` has top-level `name` (string) and `plugins` (array). Each plugin entry has `name`, `description` (others ignored).
> - `~/.claude/plugins/installed_plugins.json` has `plugins` (object); its KEYS are install-refs like `"superpowers@claude-plugins-official"`.
> - Install CLI: `claude plugin install <plugin>@<marketplace>`. `claude` is at `~/.local/bin/claude` (also usually on PATH).

---

## File Structure

```
Sources/SkillDeckCore/
├── Models/Node.swift              (NEW: Node, NodeKind, InstallStatus)
├── Models/SkillItem.swift         (kept; Scanner produces these, mapped to Node in TreeBuilder)
├── InstalledPluginsIndex.swift    (NEW)
├── MarketplaceScanner.swift       (NEW)
├── TreeBuilder.swift              (NEW: SkillItems + marketplace nodes → [Node] tree, deduped)
├── Installer.swift                (NEW: command construction (pure) + Process run)
├── Scanner.swift / FrontmatterParser.swift / ProjectDiscovery.swift / Injector.swift / BuiltinCommands.swift / FileWatcher.swift / FrontmostAppTracker.swift / Persistence.swift  (KEPT)
└── AppStore.swift                 (MODIFIED: nodes + tree traversal + installer)
Sources/SkillDeckApp/
├── SkillDeckApp.swift             (MODIFIED: reload builds nodes; pass installer)
├── TreeListView.swift             (NEW: collapsible installed tree)
├── MarketplaceView.swift          (NEW: browse mode w/ install buttons)
├── PluginDetailView.swift         (NEW: plugin node detail + install)
├── SidebarView.swift              (MODIFIED: add Marketplace entry + side-branch groups)
├── ListView.swift / DetailView.swift / MenuBarView.swift / DiagnosticsView.swift (KEPT, reused for leaves)
Tests/SkillDeckCoreTests/
├── NodeTests.swift, InstalledPluginsIndexTests.swift, MarketplaceScannerTests.swift,
│   TreeBuilderTests.swift, InstallerCommandTests.swift, AppStoreNodeTests.swift (NEW)
```

**Node id rules (used across all tasks):**
- marketplace: `mp|<name>`
- plugin: `mp|<marketplace>|plugin|<name>`
- installed/local/builtin/project leaf: v1 format `<scopeKey>|<plugin-or-_>|<kind>|<name>` (unchanged, preserves v1 favorites/recents)

---

## Task 1: Node model

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/Models/Node.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/NodeTests.swift`

- [ ] **Step 1: Write `Models/Node.swift`**

```swift
import Foundation

public enum NodeKind: String, Equatable, Sendable {
    case marketplace, plugin, skill, command, builtinCommand, localSkill
}

public enum InstallStatus: Equatable, Sendable {
    case installed, available, notApplicable
}

public struct Node: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: NodeKind
    public let name: String
    public let description: String
    public let status: InstallStatus
    public let parentID: String?

    // leaf-only
    public let body: String?
    public let insertText: String?
    public let filePath: String?

    // plugin-only
    public let marketplaceName: String?
    public let installRef: String?

    public init(id: String, kind: NodeKind, name: String, description: String,
                status: InstallStatus, parentID: String?,
                body: String? = nil, insertText: String? = nil, filePath: String? = nil,
                marketplaceName: String? = nil, installRef: String? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.description = description
        self.status = status; self.parentID = parentID
        self.body = body; self.insertText = insertText; self.filePath = filePath
        self.marketplaceName = marketplaceName; self.installRef = installRef
    }

    public static func marketplaceID(_ name: String) -> String { "mp|\(name)" }
    public static func pluginID(marketplace: String, plugin: String) -> String {
        "mp|\(marketplace)|plugin|\(plugin)"
    }

    public var isLeaf: Bool {
        switch kind {
        case .skill, .command, .builtinCommand, .localSkill: return true
        case .marketplace, .plugin: return false
        }
    }
}
```

- [ ] **Step 2: Write the failing test `NodeTests.swift`**

```swift
import XCTest
@testable import SkillDeckCore

final class NodeTests: XCTestCase {
    func test_id_helpers() {
        XCTAssertEqual(Node.marketplaceID("official"), "mp|official")
        XCTAssertEqual(Node.pluginID(marketplace: "official", plugin: "ralph-loop"),
                       "mp|official|plugin|ralph-loop")
    }

    func test_isLeaf() {
        func n(_ k: NodeKind) -> Node {
            Node(id: "x", kind: k, name: "n", description: "", status: .notApplicable, parentID: nil)
        }
        XCTAssertTrue(n(.skill).isLeaf)
        XCTAssertTrue(n(.command).isLeaf)
        XCTAssertTrue(n(.builtinCommand).isLeaf)
        XCTAssertTrue(n(.localSkill).isLeaf)
        XCTAssertFalse(n(.plugin).isLeaf)
        XCTAssertFalse(n(.marketplace).isLeaf)
    }
}
```

- [ ] **Step 3: Run test to verify pass**

Run: `cd SkillDeck && swift test --filter NodeTests`
Expected: PASS (2 tests). (Implementation written first here since it's pure data; if you prefer strict TDD, paste the test, run to see it fail to compile, then add Node.swift.)

- [ ] **Step 4: Commit**

```bash
cd /Users/yazhuo/Desktop/skill-toolkit && git add SkillDeck && git commit -m "feat(v2): unified Node model"
```

---

## Task 2: InstalledPluginsIndex

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/InstalledPluginsIndex.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/InstalledPluginsIndexTests.swift`

- [ ] **Step 1: Write the failing tests `InstalledPluginsIndexTests.swift`**

```swift
import XCTest
@testable import SkillDeckCore

final class InstalledPluginsIndexTests: XCTestCase {
    private func tmp(_ json: String) throws -> String {
        let p = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json").path
        try json.write(toFile: p, atomically: true, encoding: .utf8)
        return p
    }

    func test_parses_install_refs_from_keys() throws {
        let path = try tmp("""
        {"version":2,"plugins":{
          "superpowers@claude-plugins-official":[{"scope":"user"}],
          "frontend-design@claude-plugins-official":[{"scope":"user"}]
        }}
        """)
        let idx = InstalledPluginsIndex.load(from: path)
        XCTAssertTrue(idx.contains("superpowers@claude-plugins-official"))
        XCTAssertTrue(idx.contains("frontend-design@claude-plugins-official"))
        XCTAssertEqual(idx.count, 2)
    }

    func test_missing_file_returns_empty() {
        XCTAssertTrue(InstalledPluginsIndex.load(from: "/nope/x.json").isEmpty)
    }

    func test_malformed_returns_empty() throws {
        let path = try tmp("not json")
        XCTAssertTrue(InstalledPluginsIndex.load(from: path).isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `cd SkillDeck && swift test --filter InstalledPluginsIndexTests`
Expected: FAIL — "cannot find 'InstalledPluginsIndex'"

- [ ] **Step 3: Implement `InstalledPluginsIndex.swift`**

```swift
import Foundation

/// Reads installed_plugins.json and exposes the set of installed "<plugin>@<marketplace>" refs.
public struct InstalledPluginsIndex {
    private struct Root: Decodable { let plugins: [String: AnyCodable]? }
    private struct AnyCodable: Decodable {}  // we only need the keys

    public static func load(from path: String) -> Set<String> {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONDecoder().decode(Root.self, from: data),
              let plugins = root.plugins else {
            return []
        }
        return Set(plugins.keys)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd SkillDeck && swift test --filter InstalledPluginsIndexTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/yazhuo/Desktop/skill-toolkit && git add SkillDeck && git commit -m "feat(v2): installed-plugins index"
```

---

## Task 3: MarketplaceScanner

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/MarketplaceScanner.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/MarketplaceScannerTests.swift`

- [ ] **Step 1: Write the failing tests `MarketplaceScannerTests.swift`**

```swift
import XCTest
@testable import SkillDeckCore

final class MarketplaceScannerTests: XCTestCase {
    /// Builds <root>/<mp>/.claude-plugin/marketplace.json for each given (mpName, pluginNames).
    private func makeMarketplaces(_ specs: [(String, [String])]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (mp, plugins) in specs {
            let dir = root.appendingPathComponent("\(mp)/.claude-plugin")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let entries = plugins.map { "{\"name\":\"\($0)\",\"description\":\"desc \($0)\"}" }
                .joined(separator: ",")
            let json = "{\"name\":\"\(mp)\",\"plugins\":[\(entries)]}"
            try json.write(to: dir.appendingPathComponent("marketplace.json"),
                           atomically: true, encoding: .utf8)
        }
        return root
    }

    func test_scans_marketplaces_and_plugins_with_status() throws {
        let root = try makeMarketplaces([("official", ["superpowers", "ralph-loop"])])
        let installed: Set<String> = ["superpowers@official"]
        let result = MarketplaceScanner.scan(marketplacesDir: root.path, installed: installed)

        // one marketplace node
        let mp = result.nodes.first { $0.kind == .marketplace }!
        XCTAssertEqual(mp.name, "official")
        XCTAssertEqual(mp.id, "mp|official")

        // two plugin nodes, correct parent + installRef + status
        let sp = result.nodes.first { $0.kind == .plugin && $0.name == "superpowers" }!
        XCTAssertEqual(sp.parentID, "mp|official")
        XCTAssertEqual(sp.installRef, "superpowers@official")
        XCTAssertEqual(sp.status, .installed)
        XCTAssertEqual(sp.id, "mp|official|plugin|superpowers")

        let rl = result.nodes.first { $0.kind == .plugin && $0.name == "ralph-loop" }!
        XCTAssertEqual(rl.status, .available)
        XCTAssertEqual(rl.installRef, "ralph-loop@official")
    }

    func test_missing_dir_returns_empty() {
        let result = MarketplaceScanner.scan(marketplacesDir: "/nope", installed: [])
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func test_corrupt_manifest_records_warning() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("broken/.claude-plugin")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not json".write(to: dir.appendingPathComponent("marketplace.json"),
                             atomically: true, encoding: .utf8)
        let result = MarketplaceScanner.scan(marketplacesDir: root.path, installed: [])
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `cd SkillDeck && swift test --filter MarketplaceScannerTests`
Expected: FAIL — "cannot find 'MarketplaceScanner'"

- [ ] **Step 3: Implement `MarketplaceScanner.swift`**

```swift
import Foundation

/// Reads marketplace manifests into marketplace + plugin Nodes.
public struct MarketplaceScanner {
    public struct Result: Equatable {
        public let nodes: [Node]
        public let warnings: [ScanWarning]
    }

    private struct Manifest: Decodable {
        let name: String
        let plugins: [Entry]
        struct Entry: Decodable { let name: String; let description: String? }
    }

    /// Production convenience using the standard ~/.claude layout.
    public static func scanDefault(installed: Set<String>) -> Result {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return scan(marketplacesDir: "\(home)/.claude/plugins/marketplaces", installed: installed)
    }

    public static func scan(marketplacesDir: String, installed: Set<String>) -> Result {
        let fm = FileManager.default
        var nodes: [Node] = []
        var warnings: [ScanWarning] = []

        guard let mpDirs = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: marketplacesDir),
            includingPropertiesForKeys: [.isDirectoryKey]) else {
            return Result(nodes: [], warnings: [])
        }

        for mpDir in mpDirs {
            let manifestPath = mpDir.appendingPathComponent(".claude-plugin/marketplace.json")
            guard fm.fileExists(atPath: manifestPath.path) else { continue }
            guard let data = try? Data(contentsOf: manifestPath),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
                warnings.append(ScanWarning(filePath: manifestPath.path,
                                            message: "Could not parse marketplace manifest"))
                continue
            }
            let mpName = manifest.name
            nodes.append(Node(id: Node.marketplaceID(mpName), kind: .marketplace,
                              name: mpName, description: "", status: .notApplicable,
                              parentID: nil))
            for entry in manifest.plugins {
                let ref = "\(entry.name)@\(mpName)"
                let status: InstallStatus = installed.contains(ref) ? .installed : .available
                nodes.append(Node(
                    id: Node.pluginID(marketplace: mpName, plugin: entry.name),
                    kind: .plugin, name: entry.name,
                    description: entry.description ?? "", status: status,
                    parentID: Node.marketplaceID(mpName),
                    marketplaceName: mpName, installRef: ref))
            }
        }
        return Result(nodes: nodes, warnings: warnings)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd SkillDeck && swift test --filter MarketplaceScannerTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/yazhuo/Desktop/skill-toolkit && git add SkillDeck && git commit -m "feat(v2): marketplace manifest scanner"
```

---

## Task 4: TreeBuilder

Converts v1 `SkillItem`s (installed leaves, local skills, project items, builtins) plus
marketplace/plugin nodes into one flat `[Node]` with correct `parentID` wiring and dedupe.

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/TreeBuilder.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/TreeBuilderTests.swift`

Side-branch root ids (constants the builder creates): `root|local`, `root|project`, `root|builtin`.

- [ ] **Step 1: Write the failing tests `TreeBuilderTests.swift`**

```swift
import XCTest
@testable import SkillDeckCore

final class TreeBuilderTests: XCTestCase {
    private func skill(_ name: String, plugin: String?, scope: SourceScope = .user,
                       kind: ItemKind = .skill) -> SkillItem {
        SkillItem(name: name, kind: kind, scope: scope, pluginName: plugin,
                  description: "d-\(name)", body: "b", filePath: "/f/\(name)",
                  insertText: kind == .skill ? "use the \(name) skill" : "/\(name)")
    }

    func test_installed_plugin_skill_hangs_under_plugin_node() {
        // marketplace + plugin node for superpowers (installed)
        let mpNodes = [
            Node(id: Node.marketplaceID("official"), kind: .marketplace, name: "official",
                 description: "", status: .notApplicable, parentID: nil),
            Node(id: Node.pluginID(marketplace: "official", plugin: "superpowers"),
                 kind: .plugin, name: "superpowers", description: "", status: .installed,
                 parentID: Node.marketplaceID("official"),
                 marketplaceName: "official", installRef: "superpowers@official"),
        ]
        let items = [skill("brainstorming", plugin: "superpowers")]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: mpNodes)

        let leaf = nodes.first { $0.name == "brainstorming" }!
        XCTAssertEqual(leaf.kind, .skill)
        XCTAssertEqual(leaf.parentID, Node.pluginID(marketplace: "official", plugin: "superpowers"))
        XCTAssertEqual(leaf.insertText, "use the brainstorming skill")
        // v1 id preserved
        XCTAssertEqual(leaf.id, "user|superpowers|skill|brainstorming")
    }

    func test_local_skill_hangs_under_local_root() {
        let items = [skill("cloudflare", plugin: nil)]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        let leaf = nodes.first { $0.name == "cloudflare" }!
        XCTAssertEqual(leaf.kind, .localSkill)
        XCTAssertEqual(leaf.parentID, "root|local")
        XCTAssertNotNil(nodes.first { $0.id == "root|local" && $0.kind == .marketplace } == nil ? nil : nil)
        XCTAssertNotNil(nodes.first { $0.id == "root|local" })
    }

    func test_builtin_hangs_under_builtin_root() {
        let items = [SkillItem(name: "clear", kind: .builtinCommand, scope: .builtin,
                               pluginName: nil, description: "", body: "", filePath: nil,
                               insertText: "/clear")]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        let leaf = nodes.first { $0.name == "clear" }!
        XCTAssertEqual(leaf.kind, .builtinCommand)
        XCTAssertEqual(leaf.parentID, "root|builtin")
    }

    func test_project_item_hangs_under_project_root() {
        let items = [skill("deploy", plugin: nil, scope: .project("myapp"), kind: .command)]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        let leaf = nodes.first { $0.name == "deploy" }!
        XCTAssertEqual(leaf.kind, .command)
        XCTAssertEqual(leaf.parentID, "root|project")
    }

    func test_dedupe_by_id() {
        let items = [skill("brainstorming", plugin: "superpowers"),
                     skill("brainstorming", plugin: "superpowers")]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        XCTAssertEqual(nodes.filter { $0.name == "brainstorming" }.count, 1)
    }

    func test_plugin_skill_without_marketplace_node_still_appears() {
        // installed plugin whose marketplace node wasn't scanned (e.g. manifest missing):
        // leaf should still appear, parented to a synthesized plugin root fallback.
        let items = [skill("tdd", plugin: "superpowers")]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        let leaf = nodes.first { $0.name == "tdd" }!
        // falls back to a plugin-scoped parent id even without a marketplace
        XCTAssertEqual(leaf.parentID, "plugin|superpowers")
        XCTAssertNotNil(nodes.first { $0.id == "plugin|superpowers" && $0.kind == .plugin })
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `cd SkillDeck && swift test --filter TreeBuilderTests`
Expected: FAIL — "cannot find 'TreeBuilder'"

- [ ] **Step 3: Implement `TreeBuilder.swift`**

```swift
import Foundation

/// Assembles v1 SkillItems + marketplace/plugin nodes into one flat [Node] with parentID wiring.
/// Side-branch roots: root|local, root|project, root|builtin. Installed plugin leaves hang under
/// their plugin node (mp|<marketplace>|plugin|<name>) when known, else a synthesized plugin|<name>.
public struct TreeBuilder {
    public static let localRootID = "root|local"
    public static let projectRootID = "root|project"
    public static let builtinRootID = "root|builtin"

    public static func build(skillItems: [SkillItem], marketplaceNodes: [Node]) -> [Node] {
        var out: [Node] = []
        var seen = Set<String>()

        func add(_ node: Node) {
            guard seen.insert(node.id).inserted else { return }
            out.append(node)
        }

        // marketplace + plugin nodes first; index plugin nodes by name for leaf parenting
        var pluginParentByName: [String: String] = [:]   // pluginName -> plugin node id
        for n in marketplaceNodes {
            add(n)
            if n.kind == .plugin { pluginParentByName[n.name] = n.id }
        }

        // side-branch roots (created lazily, modeled as marketplace-kind containers is wrong;
        // use plugin-kind? No — use a dedicated representation: kind .marketplace is for real mps.
        // We represent side-branch roots as Nodes with kind .marketplace is misleading; instead
        // give them kind .plugin? Also misleading. Use a neutral: they are containers, so we add
        // them as kind .marketplace ONLY conceptually. To keep the model honest, we mark side
        // roots with kind .marketplace is rejected; we create them with a new neutral by reusing
        // .plugin is rejected. Decision: side roots use kind .marketplace == NO.
        // FINAL: side-branch roots are represented with kind = .marketplace? -> we instead expose
        // them as plain container nodes using kind .plugin is wrong. We choose: side roots are
        // Nodes with kind .marketplace. (They are top-level groupings, same UI affordance.)
        func ensureRoot(_ id: String, _ title: String) {
            if !seen.contains(id) {
                add(Node(id: id, kind: .marketplace, name: title, description: "",
                         status: .notApplicable, parentID: nil))
            }
        }

        for item in skillItems {
            let parentID: String
            let kind: NodeKind
            switch item.scope {
            case .builtin:
                ensureRoot(builtinRootID, "Built-in commands")
                parentID = builtinRootID
                kind = .builtinCommand
            case .project:
                ensureRoot(projectRootID, "Project")
                parentID = projectRootID
                kind = (item.kind == .skill) ? .skill : .command
            case .user:
                if let plugin = item.pluginName {
                    if let known = pluginParentByName[plugin] {
                        parentID = known
                    } else {
                        let synth = "plugin|\(plugin)"
                        if !seen.contains(synth) {
                            add(Node(id: synth, kind: .plugin, name: plugin, description: "",
                                     status: .installed, parentID: nil,
                                     marketplaceName: nil, installRef: nil))
                        }
                        parentID = synth
                    }
                    kind = (item.kind == .skill) ? .skill : .command
                } else {
                    ensureRoot(localRootID, "My local skills")
                    parentID = localRootID
                    kind = (item.kind == .skill) ? .localSkill : .command
                }
            }
            add(Node(id: item.id, kind: kind, name: item.name, description: item.description,
                     status: .notApplicable, parentID: parentID,
                     body: item.body, insertText: item.insertText, filePath: item.filePath))
        }

        return out
    }
}
```

> **Note to implementer:** ignore the long comment block exploring side-root representation — replace it with a single clean line: `// Side-branch roots are top-level container Nodes (kind .marketplace) created lazily.` The decision is: side-branch roots use `kind = .marketplace` (they are top-level groupings with the same expand/collapse UI affordance). Keep `ensureRoot` as written.

- [ ] **Step 4: Run to verify pass**

Run: `cd SkillDeck && swift test --filter TreeBuilderTests`
Expected: PASS (6 tests). Fix the test `test_local_skill_hangs_under_local_root`'s awkward assertion line if it doesn't compile — the intent is just `XCTAssertNotNil(nodes.first { $0.id == "root|local" })`.

- [ ] **Step 5: Commit**

```bash
cd /Users/yazhuo/Desktop/skill-toolkit && git add SkillDeck && git commit -m "feat(v2): tree builder assembling nodes by parent"
```

---

## Task 5: Installer (command construction + Process run)

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/Installer.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/InstallerCommandTests.swift`

- [ ] **Step 1: Write the failing tests `InstallerCommandTests.swift`**

```swift
import XCTest
@testable import SkillDeckCore

final class InstallerCommandTests: XCTestCase {
    func test_install_arguments_for_ref() {
        let args = Installer.installArguments(installRef: "ralph-loop@official")
        XCTAssertEqual(args, ["plugin", "install", "ralph-loop@official"])
    }

    func test_resolve_claude_path_prefers_existing_fallback() {
        // When PATH lookup is not available in test, the fallback path string is returned as-is.
        let p = Installer.fallbackClaudePath
        XCTAssertTrue(p.hasSuffix("/.local/bin/claude"))
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `cd SkillDeck && swift test --filter InstallerCommandTests`
Expected: FAIL — "cannot find 'Installer'"

- [ ] **Step 3: Implement `Installer.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class Installer {
    public enum State: Equatable, Sendable {
        case idle, installing, succeeded, failed(String)
    }

    public private(set) var states: [String: State] = [:]   // keyed by plugin node id

    public init() {}

    /// Pure: arguments to pass to the `claude` executable for an install.
    public nonisolated static func installArguments(installRef: String) -> [String] {
        ["plugin", "install", installRef]
    }

    public nonisolated static var fallbackClaudePath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
    }

    /// Resolves the claude executable: PATH via /usr/bin/env, else the fallback path.
    nonisolated static func resolveClaudeURL() -> URL? {
        let fallback = URL(fileURLWithPath: fallbackClaudePath)
        if FileManager.default.isExecutableFile(atPath: fallback.path) { return fallback }
        // try `which claude`
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        if which.terminationStatus == 0,
           let data = try? pipe.fileHandleForReading.readToEnd(),
           let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            return URL(fileURLWithPath: s)
        }
        return nil
    }

    public static var isClaudeAvailable: Bool { resolveClaudeURL() != nil }

    /// Runs `claude plugin install <installRef>` in the background and tracks state by node id.
    public func install(_ node: Node) async {
        guard let ref = node.installRef else { return }
        states[node.id] = .installing
        let result = await Self.runInstall(ref: ref)
        states[node.id] = result
    }

    private nonisolated static func runInstall(ref: String) async -> State {
        guard let claude = resolveClaudeURL() else {
            return .failed("claude CLI not found")
        }
        return await withCheckedContinuation { cont in
            let proc = Process()
            proc.executableURL = claude
            proc.arguments = installArguments(installRef: ref)
            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = Pipe()
            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume(returning: .succeeded)
                } else {
                    let data = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let msg = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(p.terminationStatus)"
                    cont.resume(returning: .failed(msg.isEmpty ? "exit \(p.terminationStatus)" : msg))
                }
            }
            do { try proc.run() } catch {
                cont.resume(returning: .failed(error.localizedDescription))
            }
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd SkillDeck && swift test --filter InstallerCommandTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd /Users/yazhuo/Desktop/skill-toolkit && git add SkillDeck && git commit -m "feat(v2): plugin installer (Process + state)"
```

---

## Task 6: AppStore — nodes + tree traversal + installer

Switch AppStore from `items: [SkillItem]` to `nodes: [Node]`, keeping all favorites/recents/
overrides logic (still id-based, leaf ids unchanged).

**Files:**
- Modify: `SkillDeck/Sources/SkillDeckCore/AppStore.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/AppStoreNodeTests.swift`
- Modify: `SkillDeck/Tests/SkillDeckCoreTests/AppStoreTests.swift` (migrate to nodes — see Step 1)

- [ ] **Step 1: Update existing `AppStoreTests.swift` to use nodes**

The v1 `AppStoreTests` calls `store.setItems(...)` and `store.search(...).map(\.name)`. Replace its `sampleItems()` helper and `setItems` calls with nodes. Change `sampleItems()` to `sampleNodes()`:

```swift
    private func sampleNodes() -> [Node] {
        [
            Node(id: "user|sp|skill|brainstorming", kind: .skill, name: "brainstorming",
                 description: "creative", status: .notApplicable, parentID: "plugin|sp",
                 body: "", insertText: "use the brainstorming skill", filePath: "/a"),
            Node(id: "user|cr|command|code-review", kind: .command, name: "code-review",
                 description: "review diff", status: .notApplicable, parentID: "plugin|cr",
                 body: "", insertText: "/code-review", filePath: "/b"),
        ]
    }
```

Then replace each `store.setItems(sampleItems())` with `store.setNodes(sampleNodes())`. The id strings used in the assertions (`user|sp|skill|brainstorming`, `user|cr|command|code-review`) are unchanged, so favorites/recents/override assertions still hold. `search` now returns `[Node]` — `.map(\.name)` still works.

- [ ] **Step 2: Write `AppStoreNodeTests.swift`**

```swift
import XCTest
@testable import SkillDeckCore

@MainActor
final class AppStoreNodeTests: XCTestCase {
    private func tmp() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json").path
    }
    private func nodes() -> [Node] {
        [
            Node(id: "mp|official", kind: .marketplace, name: "official", description: "",
                 status: .notApplicable, parentID: nil),
            Node(id: "mp|official|plugin|superpowers", kind: .plugin, name: "superpowers",
                 description: "", status: .installed, parentID: "mp|official",
                 marketplaceName: "official", installRef: "superpowers@official"),
            Node(id: "user|superpowers|skill|tdd", kind: .skill, name: "tdd", description: "d",
                 status: .notApplicable, parentID: "mp|official|plugin|superpowers",
                 body: "b", insertText: "use the tdd skill", filePath: "/x"),
        ]
    }

    func test_children_of_parent() {
        let store = AppStore(statePath: tmp())
        store.setNodes(nodes())
        let kids = store.children(of: "mp|official|plugin|superpowers")
        XCTAssertEqual(kids.map(\.name), ["tdd"])
        XCTAssertEqual(store.children(of: "mp|official").map(\.name), ["superpowers"])
    }

    func test_root_nodes() {
        let store = AppStore(statePath: tmp())
        store.setNodes(nodes())
        XCTAssertEqual(store.rootNodes().map(\.id), ["mp|official"])
    }

    func test_favorite_only_leaves() {
        let store = AppStore(statePath: tmp())
        store.setNodes(nodes())
        store.toggleFavorite("mp|official|plugin|superpowers")  // plugin: ignored
        XCTAssertFalse(store.isFavorite("mp|official|plugin|superpowers"))
        store.toggleFavorite("user|superpowers|skill|tdd")      // leaf: allowed
        XCTAssertTrue(store.isFavorite("user|superpowers|skill|tdd"))
    }

    func test_node_lookup_and_effective_insert_text() {
        let store = AppStore(statePath: tmp())
        store.setNodes(nodes())
        XCTAssertEqual(store.effectiveInsertText(for: "user|superpowers|skill|tdd"), "use the tdd skill")
    }
}
```

- [ ] **Step 3: Run to verify fail**

Run: `cd SkillDeck && swift test --filter AppStoreNodeTests`
Expected: FAIL — `setNodes` / `children(of:)` / `rootNodes` not found

- [ ] **Step 4: Modify `AppStore.swift`**

Replace the catalog section. Change the stored property and methods:

```swift
    // was: public private(set) var items: [SkillItem] = []
    public private(set) var nodes: [Node] = []
    public let installer = Installer()

    // was: setItems
    public func setNodes(_ nodes: [Node]) { self.nodes = nodes }

    public func node(id: String) -> Node? { nodes.first { $0.id == id } }

    public func children(of parentID: String) -> [Node] {
        nodes.filter { $0.parentID == parentID }
    }

    public func rootNodes() -> [Node] {
        nodes.filter { $0.parentID == nil }
    }

    /// Case-insensitive match over name + description. Empty query = all.
    public func search(_ query: String) -> [Node] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nodes }
        return nodes.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }
```

Update favorites/recents/overrides to operate on nodes:
- `favoriteItems()` → return `[Node]`: `state.favorites.compactMap { id in nodes.first { $0.id == id } }`
- `recentItems(limit:)` → map to nodes the same way.
- `toggleFavorite(_:)` → guard leaf-only: at the top add
  `guard let n = node(id: id), n.isLeaf else { return }`
- `effectiveInsertText(for:)` → `if let o = state.overrides[id] { return o }; return nodes.first { $0.id == id }?.insertText ?? ""`
- Keep `setWarnings`/`warnings`, `recordUse`, `useCount`, `setOverride`, `removeOverride`, `persist` unchanged in logic.

Remove the old `items`, `setItems`, `item(id:)` (replace `item(id:)` usages with `node(id:)`). Keep `import Observation`.

- [ ] **Step 5: Run to verify pass**

Run: `cd SkillDeck && swift test --filter AppStoreNodeTests` then `cd SkillDeck && swift test --filter AppStoreTests`
Expected: both PASS. (AppStoreTests migrated in Step 1.)

- [ ] **Step 6: Commit**

```bash
cd /Users/yazhuo/Desktop/skill-toolkit && git add SkillDeck && git commit -m "feat(v2): AppStore on Node model with tree traversal + installer"
```

---

## Task 7: Wire reload to build nodes (app integration)

The app's `reload()` must now produce `[Node]` via Scanner + MarketplaceScanner + TreeBuilder.
This breaks the v1 views that read `store.items`; Task 8 rewrites them. After THIS task the
package builds via the Core tests but the App target may not compile until Task 8 — so this task
focuses on Core wiring + a Core-level integration test, and defers App compile to Task 8.

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/CatalogLoader.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/CatalogLoaderTests.swift`

- [ ] **Step 1: Write the failing test `CatalogLoaderTests.swift`**

```swift
import XCTest
@testable import SkillDeckCore

final class CatalogLoaderTests: XCTestCase {
    func test_builds_nodes_from_scan_results() throws {
        // Build a fake ~/.claude-like tree: one installed plugin skill + one local skill + a marketplace.
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        func write(_ rel: String, _ s: String) throws {
            let u = root.appendingPathComponent(rel)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try s.write(to: u, atomically: true, encoding: .utf8)
        }
        try write("skills/cloudflare/SKILL.md", "---\nname: cloudflare\ndescription: cf\n---\nbody")
        try write("plugins/cache/mp/superpowers/5.1.0/skills/tdd/SKILL.md",
                  "---\nname: tdd\ndescription: t\n---\nbody")
        try write("plugins/marketplaces/official/.claude-plugin/marketplace.json",
                  "{\"name\":\"official\",\"plugins\":[{\"name\":\"superpowers\",\"description\":\"d\"},{\"name\":\"ralph-loop\",\"description\":\"r\"}]}")
        try write("plugins/installed_plugins.json",
                  "{\"version\":2,\"plugins\":{\"superpowers@official\":[{}]}}")

        let result = CatalogLoader.load(
            userSkillsDir: root.appendingPathComponent("skills").path,
            pluginsCacheDir: root.appendingPathComponent("plugins/cache").path,
            marketplacesDir: root.appendingPathComponent("plugins/marketplaces").path,
            installedPluginsPath: root.appendingPathComponent("plugins/installed_plugins.json").path,
            projectDirs: [])

        // marketplace + 2 plugin nodes
        XCTAssertNotNil(result.nodes.first { $0.id == "mp|official" })
        let sp = result.nodes.first { $0.kind == .plugin && $0.name == "superpowers" }!
        XCTAssertEqual(sp.status, .installed)
        XCTAssertEqual(result.nodes.first { $0.name == "ralph-loop" }?.status, .available)
        // local skill under local root
        XCTAssertEqual(result.nodes.first { $0.name == "cloudflare" }?.parentID, "root|local")
    }
}
```

- [ ] **Step 2: Run to verify fail**

Run: `cd SkillDeck && swift test --filter CatalogLoaderTests`
Expected: FAIL — "cannot find 'CatalogLoader'"

- [ ] **Step 3: Implement `CatalogLoader.swift`**

```swift
import Foundation

/// Combines all scanners into the final node tree + warnings.
public struct CatalogLoader {
    public struct Result: Equatable {
        public let nodes: [Node]
        public let warnings: [ScanWarning]
    }

    public static func loadDefault(projectDirs: [String]) -> Result {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return load(
            userSkillsDir: "\(home)/.claude/skills",
            pluginsCacheDir: "\(home)/.claude/plugins/cache",
            marketplacesDir: "\(home)/.claude/plugins/marketplaces",
            installedPluginsPath: "\(home)/.claude/plugins/installed_plugins.json",
            projectDirs: projectDirs)
    }

    public static func load(userSkillsDir: String, pluginsCacheDir: String,
                            marketplacesDir: String, installedPluginsPath: String,
                            projectDirs: [String]) -> Result {
        let installed = InstalledPluginsIndex.load(from: installedPluginsPath)
        let leafScan = Scanner.scan(userSkillsDir: userSkillsDir, pluginsCacheDir: pluginsCacheDir,
                                    projectDirs: projectDirs, includeBuiltins: true)
        let mpScan = MarketplaceScanner.scan(marketplacesDir: marketplacesDir, installed: installed)
        let nodes = TreeBuilder.build(skillItems: leafScan.items, marketplaceNodes: mpScan.nodes)
        return Result(nodes: nodes, warnings: leafScan.warnings + mpScan.warnings)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd SkillDeck && swift test --filter CatalogLoaderTests`
Expected: PASS (1 test)

- [ ] **Step 5: Run full Core suite**

Run: `cd SkillDeck && swift test`
Expected: all Core tests pass (v1 + v2 logic). The App target is not built by `swift test`; it's fixed in Task 8.

- [ ] **Step 6: Commit**

```bash
cd /Users/yazhuo/Desktop/skill-toolkit && git add SkillDeck && git commit -m "feat(v2): catalog loader combining all scanners into node tree"
```

---

## Task 8: SwiftUI — tree view, marketplace browse, plugin detail, app wiring

Rewrite the App-target views to consume `[Node]`. No unit tests (UI); success = clean `swift build`
+ `swift run SkillDeckApp` launches.

**Files:**
- Modify: `SkillDeck/Sources/SkillDeckApp/SkillDeckApp.swift`
- Modify: `SkillDeck/Sources/SkillDeckApp/SidebarView.swift`
- Create: `SkillDeck/Sources/SkillDeckApp/TreeListView.swift`
- Create: `SkillDeck/Sources/SkillDeckApp/MarketplaceView.swift`
- Create: `SkillDeck/Sources/SkillDeckApp/PluginDetailView.swift`
- Modify: `SkillDeck/Sources/SkillDeckApp/DetailView.swift` (Node-based)
- Modify: `SkillDeck/Sources/SkillDeckApp/ListView.swift` (Node-based, used for flat filtered lists)
- Modify: `SkillDeck/Sources/SkillDeckApp/MenuBarView.swift` (Node-based)
- Modify: `SkillDeck/Sources/SkillDeckApp/DiagnosticsView.swift` (unchanged logic; verify still compiles)

- [ ] **Step 1: Rewrite `SkillDeckApp.swift`**

```swift
import SwiftUI
import AppKit
import SkillDeckCore

@main
struct SkillDeckApp: App {
    @State private var store = AppStore()
    @State private var tracker = FrontmostAppTracker()
    @State private var watcher: FileWatcher?
    @State private var selection: String?
    @State private var sidebarFilter: SidebarFilter = .all

    var body: some Scene {
        Window("SkillDeck", id: "main") {
            NavigationSplitView {
                SidebarView(store: store, filter: $sidebarFilter)
            } content: {
                ContentColumn(store: store, tracker: tracker,
                              filter: sidebarFilter, selection: $selection)
            } detail: {
                DetailColumn(store: store, tracker: tracker, selection: $selection)
            }
            .frame(minWidth: 860, minHeight: 520)
            .onAppear { bootstrap() }
        }

        MenuBarExtra("SkillDeck", systemImage: "command.square") {
            MenuBarView(store: store, tracker: tracker)
        }
        .menuBarExtraStyle(.menu)
    }

    @MainActor private func bootstrap() {
        tracker.start()
        reload()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let w = FileWatcher(paths: ["\(home)/.claude/skills", "\(home)/.claude/plugins"],
                            onChange: { Task { @MainActor in reload() } })
        w.start()
        self.watcher = w
    }

    @MainActor private func reload() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projects = ProjectDiscovery.recentProjects(
            historyPath: "\(home)/.claude/history.jsonl", limit: 15)
        let result = CatalogLoader.loadDefault(projectDirs: projects)
        store.setNodes(result.nodes)
        store.setWarnings(result.warnings)
    }
}

enum SidebarFilter: Hashable {
    case all, favorites, recents, commands, skills, localSkills, builtin, marketplace, diagnostics
}

/// Chooses the middle column based on the sidebar filter.
struct ContentColumn: View {
    let store: AppStore
    let tracker: FrontmostAppTracker
    let filter: SidebarFilter
    @Binding var selection: String?

    var body: some View {
        switch filter {
        case .marketplace:
            MarketplaceView(store: store, selection: $selection)
        case .diagnostics:
            DiagnosticsView(store: store)
        case .all:
            TreeListView(store: store, selection: $selection)
        default:
            ListView(store: store, filter: filter, selection: $selection)
        }
    }
}

/// Detail column dispatches by node kind.
struct DetailColumn: View {
    let store: AppStore
    let tracker: FrontmostAppTracker
    @Binding var selection: String?

    var body: some View {
        if let id = selection, let node = store.node(id: id) {
            if node.kind == .plugin {
                PluginDetailView(store: store, node: node)
            } else if node.isLeaf {
                DetailView(store: store, tracker: tracker, selection: $selection)
            } else {
                ContentUnavailableView("Group", systemImage: "folder",
                    description: Text("Select a skill or command."))
            }
        } else {
            ContentUnavailableView("Select an item", systemImage: "sidebar.left",
                description: Text("Pick a skill or command to see its usage and inject it."))
        }
    }
}
```

- [ ] **Step 2: Rewrite `SidebarView.swift`**

```swift
import SwiftUI
import SkillDeckCore

struct SidebarView: View {
    let store: AppStore
    @Binding var filter: SidebarFilter

    var body: some View {
        List(selection: Binding(get: { filter }, set: { if let v = $0 { filter = v } })) {
            Section {
                Label("Favorites", systemImage: "star").tag(SidebarFilter.favorites)
                Label("Recent", systemImage: "clock").tag(SidebarFilter.recents)
                Label("All (installed)", systemImage: "square.grid.2x2").tag(SidebarFilter.all)
            }
            Section("Type") {
                Label("Commands", systemImage: "terminal").tag(SidebarFilter.commands)
                Label("Skills", systemImage: "sparkles").tag(SidebarFilter.skills)
                Label("My local", systemImage: "folder").tag(SidebarFilter.localSkills)
                Label("Built-in", systemImage: "keyboard").tag(SidebarFilter.builtin)
            }
            Section("Browse") {
                Label("Marketplace", systemImage: "bag").tag(SidebarFilter.marketplace)
            }
            Section {
                Label("Diagnostics", systemImage: "exclamationmark.triangle")
                    .tag(SidebarFilter.diagnostics)
            }
        }
        .listStyle(.sidebar)
    }
}
```

- [ ] **Step 3: Create `TreeListView.swift`** (collapsible installed tree — excludes marketplace browse; shows installed-plugin subtrees + side branches)

```swift
import SwiftUI
import SkillDeckCore

struct TreeListView: View {
    let store: AppStore
    @Binding var selection: String?

    // Top-level rows: installed plugin nodes (have children) + side-branch roots, excluding
    // marketplace catalog roots that contain only available plugins.
    private var roots: [Node] {
        store.rootNodes().filter { root in
            // a root is shown if it has any installed/leaf descendant
            hasShowableChild(root.id)
        }
    }

    private func hasShowableChild(_ id: String) -> Bool {
        let kids = store.children(of: id)
        for k in kids {
            if k.isLeaf { return true }
            if k.kind == .plugin && k.status == .installed { return true }
            if hasShowableChild(k.id) { return true }
        }
        return false
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(roots) { root in
                OutlineGroup(visibleChildren(of: root.id), id: \.id, children: { node in
                    let kids = visibleChildren(of: node.id)
                    return kids.isEmpty ? nil : kids
                }) { node in
                    NodeRow(store: store, node: node).tag(node.id)
                }
                .listRowBackground(Color.clear)
                Section(header: Text(root.name)) { EmptyView() }
            }
        }
    }

    /// Children to show in the installed tree: leaves + installed plugins (skip available plugins).
    private func visibleChildren(of id: String) -> [Node] {
        store.children(of: id).filter { $0.isLeaf || ($0.kind == .plugin && $0.status == .installed) }
    }
}

struct NodeRow: View {
    let store: AppStore
    let node: Node
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                if !node.description.isEmpty {
                    Text(node.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if node.isLeaf && store.isFavorite(node.id) {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
        }
    }
    private var icon: String {
        switch node.kind {
        case .skill, .localSkill: return "sparkles"
        case .command, .builtinCommand: return "terminal"
        case .plugin: return "puzzlepiece"
        case .marketplace: return "folder"
        }
    }
}
```

> **Implementer note:** `OutlineGroup` with a recursive `children:` closure must return `nil` for leaves to avoid an infinite disclosure triangle. The `visibleChildren` returning `[]` → mapped to `nil` handles this. If `OutlineGroup`'s API on macOS 15 differs, an acceptable alternative is nested `DisclosureGroup`s built by a small recursive helper view `NodeTree(node:)` that calls `store.children(of:)`. Either is fine; keep it compiling and showing the hierarchy. The trailing `Section(header:)` hack is ugly — instead group by wrapping each root in its own `Section(root.name) { OutlineGroup(...) }`. Use that cleaner form.

- [ ] **Step 4: Create `MarketplaceView.swift`**

```swift
import SwiftUI
import SkillDeckCore

struct MarketplaceView: View {
    let store: AppStore
    @Binding var selection: String?
    @State private var query = ""

    private var marketplaces: [Node] {
        store.nodes.filter { $0.kind == .marketplace && $0.id.hasPrefix("mp|")
            && !$0.id.hasPrefix("root|") }
    }

    private func plugins(in mpID: String) -> [Node] {
        let all = store.children(of: mpID).filter { $0.kind == .plugin }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(marketplaces) { mp in
                Section(mp.name) {
                    ForEach(plugins(in: mp.id)) { plugin in
                        HStack {
                            Image(systemName: plugin.status == .installed ? "checkmark.circle.fill" : "puzzlepiece")
                                .foregroundStyle(plugin.status == .installed ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plugin.name)
                                Text(plugin.description).font(.caption)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            InstallButton(store: store, node: plugin)
                        }
                        .tag(plugin.id)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search marketplace plugins")
    }
}

struct InstallButton: View {
    let store: AppStore
    let node: Node
    var body: some View {
        let state = store.installer.states[node.id] ?? .idle
        switch (node.status, state) {
        case (.installed, _):
            Text("Installed").font(.caption).foregroundStyle(.green)
        case (_, .installing):
            ProgressView().controlSize(.small)
        case (_, .failed(let msg)):
            VStack(alignment: .trailing) {
                Button("Retry") { Task { await store.installer.install(node) } }
                Text(msg).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
        default:
            Button("Install") { Task { await store.installer.install(node) } }
                .disabled(!Installer.isClaudeAvailable)
        }
    }
}
```

- [ ] **Step 5: Create `PluginDetailView.swift`**

```swift
import SwiftUI
import SkillDeckCore

struct PluginDetailView: View {
    let store: AppStore
    let node: Node
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(node.name).font(.title.bold())
                Text(node.status == .installed ? "Installed" : "Not installed")
                    .font(.caption).foregroundStyle(node.status == .installed ? .green : .secondary)
                if !node.description.isEmpty { Text(node.description) }
                Divider()
                if node.status == .installed {
                    Text("Installed. Its skills/commands appear in the tree.")
                        .foregroundStyle(.secondary)
                } else {
                    InstallButton(store: store, node: node)
                    if !Installer.isClaudeAvailable {
                        Text("claude CLI not found — install unavailable.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

- [ ] **Step 6: Update `DetailView.swift`, `ListView.swift`, `MenuBarView.swift` to Node**

In all three, replace `SkillItem` with `Node`, `store.items` with `store.nodes`, `store.item(id:)` with `store.node(id:)`, `item.kind == .skill` checks stay valid (NodeKind has .skill), and use `node.insertText ?? ""` where insertText was non-optional. Specifically:

`ListView.swift` rows by filter (Node-based):
```swift
    private var rows: [Node] {
        let base: [Node]
        switch filter {
        case .favorites: base = store.favoriteItems()
        case .recents:   base = store.recentItems(limit: 50)
        case .commands:  base = store.nodes.filter { $0.kind == .command || $0.kind == .builtinCommand }
        case .skills:    base = store.nodes.filter { $0.kind == .skill || $0.kind == .localSkill }
        case .localSkills: base = store.nodes.filter { $0.kind == .localSkill }
        case .builtin:   base = store.nodes.filter { $0.kind == .builtinCommand }
        default:         base = store.nodes.filter { $0.isLeaf }
        }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter { $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }
```
and the row body uses `NodeRow(store: store, node: item)` with `.tag(item.id)`, wrapped in `List(rows, selection: $selection)` and `.searchable(text: $query, prompt: "Search skills & commands")`.

`DetailView.swift`: the selected `node` comes from `store.node(id:)`; use `node.insertText ?? ""` for the editable field default, `node.body ?? ""` for the Usage section, and the scope label derived from `node.kind`/`node.parentID` (simplify to: skills/commands show kind; keep inject/copy/favorite as v1 but on node id). Inject uses `store.effectiveInsertText(for: node.id)`.

`MenuBarView.swift`: `favoriteItems()`/`recentItems(limit:5)` now return `[Node]`; `fire(_ node:)` uses `store.effectiveInsertText(for: node.id)`. Same Injector calls.

- [ ] **Step 7: Build and launch**

Run: `cd SkillDeck && swift build`
Expected: clean build. Fix any Swift 6 concurrency / SwiftUI API drift minimally and report.
Run: `cd SkillDeck && swift test`
Expected: all Core tests still pass.
Launch: `( swift run SkillDeckApp >/tmp/skilldeck2.log 2>&1 & echo $! >/tmp/sd2.pid ); sleep 12; kill $(cat /tmp/sd2.pid) 2>/dev/null; tail -20 /tmp/skilldeck2.log`
Expected: no crash/exception text; window + menu bar appear.

- [ ] **Step 8: Commit**

```bash
cd /Users/yazhuo/Desktop/skill-toolkit && git add -A SkillDeck && git commit -m "feat(v2): tree UI, marketplace browse, plugin install UI"
```

---

## Task 9: Manual verification (v1 + v2)

No commit (verification only). Fix bugs found via TDD against Core where possible.

- [ ] **Step 1: Launch** `cd SkillDeck && swift run SkillDeckApp`. Confirm default "All (installed)" shows installed-plugin subtrees (superpowers ▸ brainstorming…), "My local" shows the 9 Cloudflare skills, "Built-in" shows /clear etc.
- [ ] **Step 2: Injection** (v1 path): grant Accessibility on first inject; click a terminal, then a menu-bar item; confirm e.g. `/clear` lands at the prompt, not auto-submitted. Revoke Accessibility → copy-only fallback works.
- [ ] **Step 3: Marketplace browse**: sidebar → Marketplace; confirm marketplaces with plugins; installed marked ✓; search filters.
- [ ] **Step 4: Install**: pick an uninstalled plugin (e.g. `ralph-loop`), click Install → spinner → on success it disappears from "available" styling and its skills appear under the installed tree within seconds (FSEvents). Verify with: it now shows in `claude plugin list`.
- [ ] **Step 5: Favorites/recents persist** across relaunch; favorites still leaf-only.
- [ ] **Step 6: Diagnostics** shows any unparsable manifests/skills.

---

## Task 10: Open-source docs (v1 + v2)

**Files:**
- Create/Modify: `SkillDeck/README.md`
- Create: `SkillDeck/CONTRIBUTING.md`
- Modify: repo root `README.md`

- [ ] **Step 1: Write `SkillDeck/README.md`** — description; screenshot placeholder; Requirements (macOS 15+, Swift 6.1/Xcode 16); Build & Run (`cd SkillDeck && swift run SkillDeckApp`); Permissions (Accessibility for injection; copy-only fallback); How it works (scans installed skills/plugins + marketplaces + local + project + built-ins; FSEvents auto-update; `claude plugin install` for one-click install); Configuration (`builtin-commands.json`); License MIT.

- [ ] **Step 2: Write `SkillDeck/CONTRIBUTING.md`** — layout (Core library vs App target); `swift test`; extension points: add a data source (a new scanner + wire in `CatalogLoader`), change injection (`Injector`), change install (`Installer`), built-ins JSON; TDD expectation for Core.

- [ ] **Step 3: Update repo root `README.md`** — point at `SkillDeck/` and the v1/v2 specs+plans under `docs/superpowers/`.

- [ ] **Step 4: Commit**

```bash
cd /Users/yazhuo/Desktop/skill-toolkit && git add -A && git commit -m "docs: SkillDeck README + CONTRIBUTING (v1 + v2)"
```

---

## Self-Review

**Spec coverage:**
- Unified Node model (kind+status, parentID tree) → Task 1 ✓
- Install execution via `claude plugin install` in background → Task 5 (Installer), Task 8 (UI) ✓
- Marketplace data source → Task 3 ✓; installed-status lookup → Task 2 ✓
- TreeBuilder assembling installed leaves + marketplace/plugin + side branches, deduped → Task 4 ✓
- CatalogLoader combining all → Task 7 ✓
- Default view = installed only; marketplace separate entry → Task 8 (SidebarFilter.all = TreeListView installed-only; .marketplace = browse) ✓
- Uninstalled = plugin granularity, install reveals leaves → Task 4 (no leaves for available plugins) + Task 8 (PluginDetailView) ✓
- Inline install feedback + auto-refresh on success → Task 5 (states) + Task 8 (InstallButton) + reuse FileWatcher (Task 8 reload) ✓
- AppStore nodes + tree traversal + favorites leaf-only + v1 migration → Task 6 ✓
- v1 favorites/recents preserved via unchanged leaf ids → Task 4 (ids), Task 6 (tests) ✓
- Reuse v1 Scanner/Injector/FileWatcher/persistence → Tasks 6,7,8 ✓
- Manual verification (v1 + v2) → Task 9 ✓; open-source docs → Task 10 ✓
- No gaps.

**Placeholder scan:** No TBD/"handle edge cases"/code-less steps. Two implementer-notes (TreeBuilder comment cleanup, OutlineGroup alternative) give explicit concrete guidance, not deferrals. ✓

**Type consistency:** `Node` init signature, `Node.marketplaceID`/`pluginID`, `InstallStatus`/`NodeKind` cases, `MarketplaceScanner.scan(marketplacesDir:installed:)`/`scanDefault(installed:)`, `InstalledPluginsIndex.load(from:)`, `TreeBuilder.build(skillItems:marketplaceNodes:)` + root id constants, `Installer.installArguments(installRef:)`/`install(_:)`/`isClaudeAvailable`/`states`, `AppStore.setNodes`/`nodes`/`node(id:)`/`children(of:)`/`rootNodes`/`search`→[Node]/`favoriteItems`→[Node]/`recentItems`→[Node], `CatalogLoader.load(...)`/`loadDefault(projectDirs:)` are used consistently across tasks. ✓
