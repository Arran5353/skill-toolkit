# SkillDeck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS app (SkillDeck) that auto-discovers Claude Code skills/commands, shows them in a searchable window + menu bar, and injects an item's invocation text into the active terminal on click.

**Architecture:** Four independent layers — Scanner (disk → `[SkillItem]`), FileWatcher (FSEvents → change signal), Injector (clipboard + simulated ⌘V), Persistence (JSON state) — all coordinated by an `@Observable` AppStore that the SwiftUI views read.

**Tech Stack:** Swift 6.1 / SwiftUI / SwiftPM executable package (macOS 15+). `MenuBarExtra` + `Window` scenes. FSEvents (CoreServices), CGEvent + NSPasteboard (AppKit) for injection.

> **Note on packaging:** The spec mentioned `.xcodeproj`; this plan uses a **SwiftPM executable package** instead so that `swift build` / `swift test` run from the CLI (testability + cleaner open-source layout). A SwiftPM executable target runs a SwiftUI `App` fine. README documents `swift run` and an optional `.app` bundling step.

---

## File Structure

```
SkillDeck/                          (package root, inside repo)
├── Package.swift                   # SwiftPM manifest: executable + test targets
├── README.md                       # screenshots, install, permissions, contributing
├── LICENSE                         # MIT
├── CONTRIBUTING.md
├── Sources/
│   ├── SkillDeckCore/              # library target (all pure logic + AppKit glue) — testable
│   │   ├── Models/
│   │   │   ├── SkillItem.swift     # SkillItem, ItemKind, SourceScope
│   │   │   └── Diagnostics.swift   # ScanWarning
│   │   ├── FrontmatterParser.swift # split YAML frontmatter / body, read name+description
│   │   ├── BuiltinCommands.swift   # built-in slash command list + loader
│   │   ├── ProjectDiscovery.swift  # parse history.jsonl → recent project paths
│   │   ├── Scanner.swift           # walk dirs → [SkillItem] + [ScanWarning]
│   │   ├── FileWatcher.swift       # FSEvents wrapper → debounced callback
│   │   ├── Injector.swift          # insertText generation + clipboard/⌘V injection
│   │   ├── FrontmostAppTracker.swift # tracks previously-frontmost app
│   │   ├── Persistence.swift       # read/write state.json
│   │   └── AppStore.swift          # @Observable: items, favorites, recents, overrides
│   ├── builtin-commands.json       # data file (bundled resource)
│   └── SkillDeckApp/               # executable target (SwiftUI views + @main)
│       ├── SkillDeckApp.swift      # @main App: Window + MenuBarExtra
│       ├── SidebarView.swift
│       ├── ListView.swift
│       ├── DetailView.swift
│       ├── MenuBarView.swift
│       └── DiagnosticsView.swift
└── Tests/
    └── SkillDeckCoreTests/
        ├── FrontmatterParserTests.swift
        ├── ScannerTests.swift
        ├── ProjectDiscoveryTests.swift
        ├── BuiltinCommandsTests.swift
        ├── InjectorTests.swift
        ├── PersistenceTests.swift
        ├── AppStoreTests.swift
        └── Fixtures/               # temp dir trees built in code; no checked-in fixtures
```

**Why this split:** All logic lives in `SkillDeckCore` (a library) so tests link against it. The executable target only holds SwiftUI views + `@main`. Files that change together (a model + its tests) are paired; each file has one responsibility.

**Stable id format (used everywhere):** `"<scopeKey>|<plugin-or-_>|<kind>|<name>"`, where `scopeKey` is `user`, `builtin`, or `project:<name>`, and missing plugin is the literal `_`. Example: `user|superpowers|skill|brainstorming`.

---

## Task 1: SwiftPM package skeleton + models

**Files:**
- Create: `SkillDeck/Package.swift`
- Create: `SkillDeck/Sources/SkillDeckCore/Models/SkillItem.swift`
- Create: `SkillDeck/Sources/SkillDeckCore/Models/Diagnostics.swift`
- Create: `SkillDeck/LICENSE`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/SkillItemTests.swift`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SkillDeck",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "SkillDeckCore",
            resources: [.copy("../builtin-commands.json")]
        ),
        .executableTarget(
            name: "SkillDeckApp",
            dependencies: ["SkillDeckCore"]
        ),
        .testTarget(
            name: "SkillDeckCoreTests",
            dependencies: ["SkillDeckCore"]
        ),
    ]
)
```

> If the relative resource path errors, move `builtin-commands.json` into `Sources/SkillDeckCore/Resources/` and use `.copy("Resources/builtin-commands.json")`. Task 5 handles the resource; adjust there if needed.

- [ ] **Step 2: Create `Models/SkillItem.swift`**

```swift
import Foundation

public enum ItemKind: String, Codable, Sendable {
    case skill, command, builtinCommand
}

public enum SourceScope: Equatable, Sendable {
    case user
    case project(String)
    case builtin

    public var key: String {
        switch self {
        case .user: return "user"
        case .builtin: return "builtin"
        case .project(let name): return "project:\(name)"
        }
    }
}

public struct SkillItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: ItemKind
    public let scope: SourceScope
    public let pluginName: String?
    public let description: String
    public let body: String
    public let filePath: String?
    public var insertText: String

    public init(name: String, kind: ItemKind, scope: SourceScope,
                pluginName: String?, description: String, body: String,
                filePath: String?, insertText: String) {
        self.id = SkillItem.makeID(scope: scope, pluginName: pluginName, kind: kind, name: name)
        self.name = name
        self.kind = kind
        self.scope = scope
        self.pluginName = pluginName
        self.description = description
        self.body = body
        self.filePath = filePath
        self.insertText = insertText
    }

    public static func makeID(scope: SourceScope, pluginName: String?,
                              kind: ItemKind, name: String) -> String {
        "\(scope.key)|\(pluginName ?? "_")|\(kind.rawValue)|\(name)"
    }
}
```

- [ ] **Step 3: Create `Models/Diagnostics.swift`**

```swift
import Foundation

public struct ScanWarning: Equatable, Sendable {
    public let filePath: String
    public let message: String
    public init(filePath: String, message: String) {
        self.filePath = filePath
        self.message = message
    }
}
```

- [ ] **Step 4: Create `LICENSE`** (MIT, year 2026, author "Yazhuo Zhou"). Use the standard MIT text.

- [ ] **Step 5: Write the failing test `SkillItemTests.swift`**

```swift
import XCTest
@testable import SkillDeckCore

final class SkillItemTests: XCTestCase {
    func test_id_is_stable_and_ignores_file_path() {
        let a = SkillItem(name: "brainstorming", kind: .skill, scope: .user,
                          pluginName: "superpowers", description: "d", body: "b",
                          filePath: "/old/5.1.0/SKILL.md", insertText: "x")
        let b = SkillItem(name: "brainstorming", kind: .skill, scope: .user,
                          pluginName: "superpowers", description: "d2", body: "b2",
                          filePath: "/new/6.0.0/SKILL.md", insertText: "y")
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.id, "user|superpowers|skill|brainstorming")
    }

    func test_id_for_project_and_nil_plugin() {
        let item = SkillItem(name: "deploy", kind: .command, scope: .project("paperwork"),
                             pluginName: nil, description: "", body: "",
                             filePath: nil, insertText: "/deploy")
        XCTAssertEqual(item.id, "project:paperwork|_|command|deploy")
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd SkillDeck && swift test --filter SkillItemTests`
Expected: PASS (2 tests). If the package doesn't build yet because `builtin-commands.json` is missing, create an empty `Sources/SkillDeckCore/builtin-commands.json` containing `[]` to satisfy the resource, then re-run.

- [ ] **Step 7: Commit**

```bash
git add SkillDeck/Package.swift SkillDeck/Sources/SkillDeckCore/Models SkillDeck/LICENSE SkillDeck/Tests/SkillDeckCoreTests/SkillItemTests.swift SkillDeck/Sources/SkillDeckCore/builtin-commands.json
git commit -m "feat: SkillDeck package skeleton + SkillItem model with stable id"
```

---

## Task 2: Frontmatter parser

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/FrontmatterParser.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/FrontmatterParserTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SkillDeckCore

final class FrontmatterParserTests: XCTestCase {
    func test_parses_name_and_description_and_body() {
        let text = """
        ---
        name: brainstorming
        description: Use this before any creative work.
        ---

        # Brainstorming

        Body line.
        """
        let r = FrontmatterParser.parse(text)
        XCTAssertEqual(r.frontmatter["name"], "brainstorming")
        XCTAssertEqual(r.frontmatter["description"], "Use this before any creative work.")
        XCTAssertTrue(r.body.contains("# Brainstorming"))
        XCTAssertFalse(r.body.contains("name:"))
    }

    func test_no_frontmatter_returns_empty_map_and_full_body() {
        let r = FrontmatterParser.parse("Just a body, no fence.")
        XCTAssertTrue(r.frontmatter.isEmpty)
        XCTAssertEqual(r.body, "Just a body, no fence.")
    }

    func test_malformed_frontmatter_does_not_crash() {
        let r = FrontmatterParser.parse("---\nthis is : : broken\n")  // no closing fence
        XCTAssertTrue(r.frontmatter.isEmpty)
        XCTAssertTrue(r.body.contains("broken"))
    }

    func test_empty_string() {
        let r = FrontmatterParser.parse("")
        XCTAssertTrue(r.frontmatter.isEmpty)
        XCTAssertEqual(r.body, "")
    }

    func test_value_with_colon_is_preserved() {
        let text = "---\ndescription: a: b: c\n---\nbody"
        let r = FrontmatterParser.parse(text)
        XCTAssertEqual(r.frontmatter["description"], "a: b: c")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillDeck && swift test --filter FrontmatterParserTests`
Expected: FAIL — "cannot find 'FrontmatterParser' in scope"

- [ ] **Step 3: Implement `FrontmatterParser.swift`**

```swift
import Foundation

public struct FrontmatterParser {
    public struct Result: Equatable {
        public let frontmatter: [String: String]
        public let body: String
    }

    /// Parses a `---`-fenced YAML-ish frontmatter block (flat key: value pairs only).
    /// Tolerant: missing/closing fence → empty frontmatter, whole text as body.
    public static func parse(_ text: String) -> Result {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return Result(frontmatter: [:], body: text)
        }
        // find closing fence
        var closing: Int? = nil
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            closing = i; break
        }
        guard let end = closing else {
            return Result(frontmatter: [:], body: text)
        }
        var map: [String: String] = [:]
        for i in 1..<end {
            let line = lines[i]
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { map[key] = value }
        }
        let body = lines[(end + 1)...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(frontmatter: map, body: body)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillDeck && swift test --filter FrontmatterParserTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add SkillDeck/Sources/SkillDeckCore/FrontmatterParser.swift SkillDeck/Tests/SkillDeckCoreTests/FrontmatterParserTests.swift
git commit -m "feat: tolerant frontmatter parser"
```

---

## Task 3: Project discovery from history.jsonl

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/ProjectDiscovery.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/ProjectDiscoveryTests.swift`

`history.jsonl` lines look like: `{"display":"...","timestamp":1759045943160,"project":"/Users/x/Desktop/foo"}`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SkillDeckCore

final class ProjectDiscoveryTests: XCTestCase {
    func test_returns_unique_projects_most_recent_first() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("history.jsonl")
        let content = """
        {"display":"a","timestamp":100,"project":"/p/alpha"}
        {"display":"b","timestamp":300,"project":"/p/beta"}
        {"display":"c","timestamp":200,"project":"/p/alpha"}
        """
        try content.write(to: file, atomically: true, encoding: .utf8)

        let projects = ProjectDiscovery.recentProjects(historyPath: file.path, limit: 10)
        XCTAssertEqual(projects, ["/p/beta", "/p/alpha"]) // beta ts300 > alpha latest ts200
    }

    func test_respects_limit() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("history.jsonl")
        try "{\"timestamp\":1,\"project\":\"/a\"}\n{\"timestamp\":2,\"project\":\"/b\"}"
            .write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectDiscovery.recentProjects(historyPath: file.path, limit: 1), ["/b"])
    }

    func test_missing_file_returns_empty() {
        XCTAssertEqual(ProjectDiscovery.recentProjects(historyPath: "/nope/x.jsonl", limit: 5), [])
    }

    func test_skips_malformed_lines() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("history.jsonl")
        try "not json\n{\"timestamp\":5,\"project\":\"/good\"}\n{}"
            .write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectDiscovery.recentProjects(historyPath: file.path, limit: 5), ["/good"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillDeck && swift test --filter ProjectDiscoveryTests`
Expected: FAIL — "cannot find 'ProjectDiscovery' in scope"

- [ ] **Step 3: Implement `ProjectDiscovery.swift`**

```swift
import Foundation

public struct ProjectDiscovery {
    private struct Line: Decodable { let timestamp: Double?; let project: String? }

    /// Returns unique project paths ordered by most-recent timestamp first, up to `limit`.
    public static func recentProjects(historyPath: String, limit: Int) -> [String] {
        guard let content = try? String(contentsOfFile: historyPath, encoding: .utf8) else {
            return []
        }
        var latest: [String: Double] = [:]
        let decoder = JSONDecoder()
        for raw in content.split(separator: "\n") {
            guard let data = raw.data(using: .utf8),
                  let line = try? decoder.decode(Line.self, from: data),
                  let project = line.project else { continue }
            let ts = line.timestamp ?? 0
            if let existing = latest[project] { latest[project] = max(existing, ts) }
            else { latest[project] = ts }
        }
        return latest.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillDeck && swift test --filter ProjectDiscoveryTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add SkillDeck/Sources/SkillDeckCore/ProjectDiscovery.swift SkillDeck/Tests/SkillDeckCoreTests/ProjectDiscoveryTests.swift
git commit -m "feat: infer recent projects from history.jsonl"
```

---

## Task 4: Injector — insertText generation (pure logic)

Injection of keystrokes can't be unit-tested; this task covers only the **insertText derivation**, which can. Actual ⌘V injection is added in Task 9.

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/Injector.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/InjectorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SkillDeckCore

final class InjectorTests: XCTestCase {
    func test_command_inserts_slash_name() {
        XCTAssertEqual(Injector.defaultInsertText(kind: .command, name: "code-review"), "/code-review")
    }
    func test_builtin_inserts_slash_name() {
        XCTAssertEqual(Injector.defaultInsertText(kind: .builtinCommand, name: "clear"), "/clear")
    }
    func test_skill_inserts_natural_language_hint() {
        XCTAssertEqual(Injector.defaultInsertText(kind: .skill, name: "brainstorming"),
                       "use the brainstorming skill")
    }
    func test_already_slashed_command_not_double_slashed() {
        XCTAssertEqual(Injector.defaultInsertText(kind: .command, name: "/deploy"), "/deploy")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillDeck && swift test --filter InjectorTests`
Expected: FAIL — "cannot find 'Injector' in scope"

- [ ] **Step 3: Implement `Injector.swift` (logic only for now)**

```swift
import Foundation

public struct Injector {
    /// Derives the default text to insert for an item.
    public static func defaultInsertText(kind: ItemKind, name: String) -> String {
        switch kind {
        case .command, .builtinCommand:
            return name.hasPrefix("/") ? name : "/\(name)"
        case .skill:
            return "use the \(name) skill"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillDeck && swift test --filter InjectorTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add SkillDeck/Sources/SkillDeckCore/Injector.swift SkillDeck/Tests/SkillDeckCoreTests/InjectorTests.swift
git commit -m "feat: insertText derivation for skills and commands"
```

---

## Task 5: Built-in commands list + loader

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/builtin-commands.json` (overwrite the `[]` placeholder)
- Create: `SkillDeck/Sources/SkillDeckCore/BuiltinCommands.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/BuiltinCommandsTests.swift`

- [ ] **Step 1: Write `builtin-commands.json`**

```json
[
  {"name": "clear", "description": "Clear the conversation history and free up context."},
  {"name": "config", "description": "Open the Claude Code settings/config UI."},
  {"name": "review", "description": "Review a pull request."},
  {"name": "init", "description": "Initialize a new CLAUDE.md with codebase documentation."},
  {"name": "help", "description": "Show help and available commands."}
]
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import SkillDeckCore

final class BuiltinCommandsTests: XCTestCase {
    func test_loads_builtins_from_bundle_as_skill_items() {
        let items = BuiltinCommands.load()
        XCTAssertFalse(items.isEmpty)
        let clear = items.first { $0.name == "clear" }
        XCTAssertNotNil(clear)
        XCTAssertEqual(clear?.kind, .builtinCommand)
        XCTAssertEqual(clear?.scope, .builtin)
        XCTAssertEqual(clear?.insertText, "/clear")
        XCTAssertNil(clear?.filePath)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd SkillDeck && swift test --filter BuiltinCommandsTests`
Expected: FAIL — "cannot find 'BuiltinCommands' in scope"

- [ ] **Step 4: Implement `BuiltinCommands.swift`**

```swift
import Foundation

public struct BuiltinCommands {
    private struct Entry: Decodable { let name: String; let description: String }

    /// Loads built-in commands bundled with the SkillDeckCore module.
    public static func load() -> [SkillItem] {
        guard let url = Bundle.module.url(forResource: "builtin-commands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries.map { e in
            SkillItem(name: e.name, kind: .builtinCommand, scope: .builtin,
                      pluginName: nil, description: e.description, body: "",
                      filePath: nil,
                      insertText: Injector.defaultInsertText(kind: .builtinCommand, name: e.name))
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd SkillDeck && swift test --filter BuiltinCommandsTests`
Expected: PASS (1 test). If it fails with a resource-not-found error, the resource path in `Package.swift` is wrong — move the JSON to `Sources/SkillDeckCore/Resources/builtin-commands.json` and set the manifest to `.copy("Resources/builtin-commands.json")`, then re-run.

- [ ] **Step 6: Commit**

```bash
git add SkillDeck/Sources/SkillDeckCore/builtin-commands.json SkillDeck/Sources/SkillDeckCore/BuiltinCommands.swift SkillDeck/Tests/SkillDeckCoreTests/BuiltinCommandsTests.swift
git commit -m "feat: built-in commands list and loader"
```

---

## Task 6: Scanner — walk directories into SkillItems

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/Scanner.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/ScannerTests.swift`

The Scanner takes explicit root paths (injected for testability) and returns items + warnings.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SkillDeckCore

final class ScannerTests: XCTestCase {
    /// Builds: <root>/skills/brainstorming/SKILL.md (user top-level skill)
    ///         <root>/plugins/cache/mp/superpowers/5.1.0/skills/tdd/SKILL.md (plugin skill)
    ///         <root>/plugins/cache/mp/superpowers/5.1.0/commands/cr.md (plugin command)
    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        func write(_ rel: String, _ contents: String) throws {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("skills/brainstorming/SKILL.md",
                  "---\nname: brainstorming\ndescription: BS\n---\nbody bs")
        try write("plugins/cache/mp/superpowers/5.1.0/skills/tdd/SKILL.md",
                  "---\nname: tdd\ndescription: TDD\n---\nbody tdd")
        try write("plugins/cache/mp/superpowers/5.1.0/commands/cr.md",
                  "---\ndescription: Code review\n---\nbody cr")
        return root
    }

    func test_scans_user_plugin_skills_and_commands() throws {
        let root = try makeTree()
        let result = Scanner.scan(
            userSkillsDir: root.appendingPathComponent("skills").path,
            pluginsCacheDir: root.appendingPathComponent("plugins/cache").path,
            projectDirs: [],
            includeBuiltins: false
        )
        let names = Set(result.items.map { $0.name })
        XCTAssertEqual(names, ["brainstorming", "tdd", "cr"])

        let tdd = result.items.first { $0.name == "tdd" }!
        XCTAssertEqual(tdd.pluginName, "superpowers")
        XCTAssertEqual(tdd.kind, .skill)
        XCTAssertEqual(tdd.scope, .user)

        let cr = result.items.first { $0.name == "cr" }!
        XCTAssertEqual(cr.kind, .command)
        XCTAssertEqual(cr.pluginName, "superpowers")
        XCTAssertEqual(cr.insertText, "/cr")

        let top = result.items.first { $0.name == "brainstorming" }!
        XCTAssertNil(top.pluginName)
        XCTAssertEqual(top.insertText, "use the brainstorming skill")
    }

    func test_command_name_falls_back_to_filename() throws {
        let root = try makeTree()
        let result = Scanner.scan(
            userSkillsDir: root.appendingPathComponent("skills").path,
            pluginsCacheDir: root.appendingPathComponent("plugins/cache").path,
            projectDirs: [], includeBuiltins: false
        )
        XCTAssertNotNil(result.items.first { $0.name == "cr" }) // cr.md, no name in frontmatter
    }

    func test_project_scope_items() throws {
        let fm = FileManager.default
        let proj = fm.temporaryDirectory.appendingPathComponent("proj-" + UUID().uuidString)
        let cmd = proj.appendingPathComponent(".claude/commands/deploy.md")
        try fm.createDirectory(at: cmd.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\ndescription: Deploy\n---\nrun it".write(to: cmd, atomically: true, encoding: .utf8)

        let result = Scanner.scan(userSkillsDir: "/nope", pluginsCacheDir: "/nope",
                                  projectDirs: [proj.path], includeBuiltins: false)
        let deploy = result.items.first { $0.name == "deploy" }!
        XCTAssertEqual(deploy.scope, .project(proj.lastPathComponent))
        XCTAssertEqual(deploy.insertText, "/deploy")
    }

    func test_empty_file_records_warning_not_crash() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s = root.appendingPathComponent("skills/broken/SKILL.md")
        try fm.createDirectory(at: s.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: s, atomically: true, encoding: .utf8)
        let result = Scanner.scan(userSkillsDir: root.appendingPathComponent("skills").path,
                                  pluginsCacheDir: "/nope", projectDirs: [], includeBuiltins: false)
        // empty skill: name falls back to dir "broken", still an item, plus a warning
        XCTAssertNotNil(result.items.first { $0.name == "broken" })
        XCTAssertFalse(result.warnings.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillDeck && swift test --filter ScannerTests`
Expected: FAIL — "cannot find 'Scanner' in scope"

- [ ] **Step 3: Implement `Scanner.swift`**

```swift
import Foundation

public struct Scanner {
    public struct Result: Equatable {
        public let items: [SkillItem]
        public let warnings: [ScanWarning]
    }

    private static let fm = FileManager.default

    /// Production convenience using the standard ~/.claude layout.
    public static func scanDefault(projectDirs: [String]) -> Result {
        let home = fm.homeDirectoryForCurrentUser.path
        return scan(
            userSkillsDir: "\(home)/.claude/skills",
            pluginsCacheDir: "\(home)/.claude/plugins/cache",
            projectDirs: projectDirs,
            includeBuiltins: true
        )
    }

    public static func scan(userSkillsDir: String, pluginsCacheDir: String,
                            projectDirs: [String], includeBuiltins: Bool) -> Result {
        var items: [SkillItem] = []
        var warnings: [ScanWarning] = []

        // 1. user top-level skills: <userSkillsDir>/<name>/SKILL.md
        scanSkillDirs(in: userSkillsDir, scope: .user, pluginName: nil,
                      items: &items, warnings: &warnings)

        // 2. plugin skills + commands: <cache>/<marketplace>/<plugin>/<ver>/skills|commands
        for marketplace in subdirectories(of: pluginsCacheDir) {
            for plugin in subdirectories(of: marketplace.path) {
                let pluginName = plugin.lastPathComponent
                for version in subdirectories(of: plugin.path) {
                    scanSkillDirs(in: version.appendingPathComponent("skills").path,
                                  scope: .user, pluginName: pluginName,
                                  items: &items, warnings: &warnings)
                    scanCommandFiles(in: version.appendingPathComponent("commands").path,
                                     scope: .user, pluginName: pluginName,
                                     items: &items, warnings: &warnings)
                }
            }
        }

        // 3. project-level: <project>/.claude/skills, <project>/.claude/commands
        for project in projectDirs {
            let name = (project as NSString).lastPathComponent
            scanSkillDirs(in: "\(project)/.claude/skills", scope: .project(name),
                          pluginName: nil, items: &items, warnings: &warnings)
            scanCommandFiles(in: "\(project)/.claude/commands", scope: .project(name),
                             pluginName: nil, items: &items, warnings: &warnings)
        }

        // 4. built-ins
        if includeBuiltins { items.append(contentsOf: BuiltinCommands.load()) }

        return Result(items: items, warnings: warnings)
    }

    // MARK: - Helpers

    private static func subdirectories(of path: String) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func scanSkillDirs(in dir: String, scope: SourceScope, pluginName: String?,
                                      items: inout [SkillItem], warnings: inout [ScanWarning]) {
        for sub in subdirectories(of: dir) {
            let file = sub.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: file.path) else { continue }
            let dirName = sub.lastPathComponent
            appendParsed(file: file.path, fallbackName: dirName, kind: .skill,
                         scope: scope, pluginName: pluginName, items: &items, warnings: &warnings)
        }
    }

    private static func scanCommandFiles(in dir: String, scope: SourceScope, pluginName: String?,
                                         items: inout [SkillItem], warnings: inout [ScanWarning]) {
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for entry in entries where entry.hasSuffix(".md") {
            let path = "\(dir)/\(entry)"
            let base = (entry as NSString).deletingPathExtension
            appendParsed(file: path, fallbackName: base, kind: .command,
                         scope: scope, pluginName: pluginName, items: &items, warnings: &warnings)
        }
    }

    private static func appendParsed(file: String, fallbackName: String, kind: ItemKind,
                                     scope: SourceScope, pluginName: String?,
                                     items: inout [SkillItem], warnings: inout [ScanWarning]) {
        let text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        if text.isEmpty {
            warnings.append(ScanWarning(filePath: file, message: "Empty file"))
        }
        let parsed = FrontmatterParser.parse(text)
        if parsed.frontmatter.isEmpty && !text.isEmpty {
            warnings.append(ScanWarning(filePath: file, message: "No frontmatter found"))
        }
        let name = parsed.frontmatter["name"] ?? fallbackName
        let item = SkillItem(
            name: name, kind: kind, scope: scope, pluginName: pluginName,
            description: parsed.frontmatter["description"] ?? "",
            body: parsed.body, filePath: file,
            insertText: Injector.defaultInsertText(kind: kind, name: name)
        )
        items.append(item)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillDeck && swift test --filter ScannerTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add SkillDeck/Sources/SkillDeckCore/Scanner.swift SkillDeck/Tests/SkillDeckCoreTests/ScannerTests.swift
git commit -m "feat: scanner for user/plugin/project skills and commands"
```

---

## Task 7: Persistence — state.json round-trip

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/Persistence.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/PersistenceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SkillDeckCore

final class PersistenceTests: XCTestCase {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json").path
    }

    func test_round_trip_preserves_state() throws {
        let path = tempPath()
        var state = PersistedState()
        state.favorites = ["user|superpowers|skill|brainstorming"]
        state.recents = [RecentEntry(id: "a", lastUsed: 123.0, count: 7)]
        state.overrides = ["a": "use the a skill"]
        try Persistence.save(state, to: path)

        let loaded = try Persistence.load(from: path)
        XCTAssertEqual(loaded, state)
    }

    func test_load_missing_file_returns_empty_state() throws {
        let loaded = try Persistence.load(from: "/nope/missing.json")
        XCTAssertEqual(loaded, PersistedState())
    }

    func test_favorites_survive_plugin_path_change() throws {
        // The id has no path in it, so a favorite stays valid across version bumps.
        let path = tempPath()
        var state = PersistedState()
        state.favorites = ["user|superpowers|skill|brainstorming"]
        try Persistence.save(state, to: path)
        let loaded = try Persistence.load(from: path)
        XCTAssertTrue(loaded.favorites.contains("user|superpowers|skill|brainstorming"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillDeck && swift test --filter PersistenceTests`
Expected: FAIL — "cannot find 'PersistedState' / 'Persistence' in scope"

- [ ] **Step 3: Implement `Persistence.swift`**

```swift
import Foundation

public struct RecentEntry: Codable, Equatable, Sendable {
    public var id: String
    public var lastUsed: Double   // epoch seconds
    public var count: Int
    public init(id: String, lastUsed: Double, count: Int) {
        self.id = id; self.lastUsed = lastUsed; self.count = count
    }
}

public struct PersistedState: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var favorites: [String] = []
    public var recents: [RecentEntry] = []
    public var overrides: [String: String] = [:]
    public init() {}
}

public struct Persistence {
    /// Default location: ~/Library/Application Support/SkillDeck/state.json
    public static func defaultPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SkillDeck/state.json").path
    }

    public static func load(from path: String) throws -> PersistedState {
        guard FileManager.default.fileExists(atPath: path) else { return PersistedState() }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(PersistedState.self, from: data)
    }

    public static func save(_ state: PersistedState, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillDeck && swift test --filter PersistenceTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add SkillDeck/Sources/SkillDeckCore/Persistence.swift SkillDeck/Tests/SkillDeckCoreTests/PersistenceTests.swift
git commit -m "feat: JSON persistence for favorites/recents/overrides"
```

---

## Task 8: AppStore — favorites, recents, search, override (pure logic)

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/AppStore.swift`
- Test: `SkillDeck/Tests/SkillDeckCoreTests/AppStoreTests.swift`

This is the coordinator. To keep it unit-testable, the persistence path is injectable and file-watching is added in the executable target (Task 9), not here.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import SkillDeckCore

@MainActor
final class AppStoreTests: XCTestCase {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json").path
    }

    private func sampleItems() -> [SkillItem] {
        [
            SkillItem(name: "brainstorming", kind: .skill, scope: .user, pluginName: "sp",
                      description: "creative", body: "", filePath: "/a", insertText: "use the brainstorming skill"),
            SkillItem(name: "code-review", kind: .command, scope: .user, pluginName: "cr",
                      description: "review diff", body: "", filePath: "/b", insertText: "/code-review"),
        ]
    }

    func test_toggle_favorite_persists() throws {
        let path = tempPath()
        let store = AppStore(statePath: path)
        store.setItems(sampleItems())
        let id = "user|sp|skill|brainstorming"
        store.toggleFavorite(id)
        XCTAssertTrue(store.isFavorite(id))

        let reloaded = AppStore(statePath: path)
        XCTAssertTrue(reloaded.state.favorites.contains(id))
    }

    func test_record_use_updates_recents_count_and_order() {
        let store = AppStore(statePath: tempPath())
        store.setItems(sampleItems())
        store.recordUse("user|cr|command|code-review")
        store.recordUse("user|sp|skill|brainstorming")
        store.recordUse("user|cr|command|code-review")
        let recents = store.recentItems(limit: 10)
        XCTAssertEqual(recents.first?.name, "code-review") // most recent
        XCTAssertEqual(store.useCount("user|cr|command|code-review"), 2)
    }

    func test_search_matches_name_description_plugin() {
        let store = AppStore(statePath: tempPath())
        store.setItems(sampleItems())
        XCTAssertEqual(store.search("brain").map(\.name), ["brainstorming"])
        XCTAssertEqual(store.search("review").map(\.name), ["code-review"]) // description match
        XCTAssertEqual(Set(store.search("").map(\.name)), ["brainstorming", "code-review"])
    }

    func test_override_changes_effective_insert_text() {
        let path = tempPath()
        let store = AppStore(statePath: path)
        store.setItems(sampleItems())
        let id = "user|sp|skill|brainstorming"
        store.setOverride(id, text: "/brainstorm")
        XCTAssertEqual(store.effectiveInsertText(for: id), "/brainstorm")

        let reloaded = AppStore(statePath: path)
        reloaded.setItems(sampleItems())
        XCTAssertEqual(reloaded.effectiveInsertText(for: id), "/brainstorm")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd SkillDeck && swift test --filter AppStoreTests`
Expected: FAIL — "cannot find 'AppStore' in scope"

- [ ] **Step 3: Implement `AppStore.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    public private(set) var items: [SkillItem] = []
    public private(set) var warnings: [ScanWarning] = []
    public private(set) var state: PersistedState

    private let statePath: String

    public init(statePath: String = Persistence.defaultPath()) {
        self.statePath = statePath
        self.state = (try? Persistence.load(from: statePath)) ?? PersistedState()
    }

    // MARK: - Catalog

    public func setItems(_ items: [SkillItem]) { self.items = items }
    public func setWarnings(_ warnings: [ScanWarning]) { self.warnings = warnings }

    public func item(id: String) -> SkillItem? { items.first { $0.id == id } }

    /// Case-insensitive match over name + description + plugin name. Empty query = all.
    public func search(_ query: String) -> [SkillItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.name.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
            || ($0.pluginName?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: - Favorites

    public func isFavorite(_ id: String) -> Bool { state.favorites.contains(id) }

    public func toggleFavorite(_ id: String) {
        if let idx = state.favorites.firstIndex(of: id) { state.favorites.remove(at: idx) }
        else { state.favorites.append(id) }
        persist()
    }

    public func favoriteItems() -> [SkillItem] {
        state.favorites.compactMap { id in items.first { $0.id == id } }
    }

    // MARK: - Recents

    public func recordUse(_ id: String, now: Double = Date().timeIntervalSince1970) {
        if let idx = state.recents.firstIndex(where: { $0.id == id }) {
            state.recents[idx].count += 1
            state.recents[idx].lastUsed = now
        } else {
            state.recents.append(RecentEntry(id: id, lastUsed: now, count: 1))
        }
        persist()
    }

    public func useCount(_ id: String) -> Int {
        state.recents.first { $0.id == id }?.count ?? 0
    }

    public func recentItems(limit: Int) -> [SkillItem] {
        state.recents.sorted { $0.lastUsed > $1.lastUsed }
            .prefix(limit)
            .compactMap { entry in items.first { $0.id == entry.id } }
    }

    // MARK: - Overrides / effective insert text

    public func setOverride(_ id: String, text: String) {
        state.overrides[id] = text
        persist()
    }

    public func effectiveInsertText(for id: String) -> String {
        if let override = state.overrides[id] { return override }
        return items.first { $0.id == id }?.insertText ?? ""
    }

    // MARK: - Private

    private func persist() { try? Persistence.save(state, to: statePath) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd SkillDeck && swift test --filter AppStoreTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Run the full suite**

Run: `cd SkillDeck && swift test`
Expected: PASS (all tasks 1–8 green)

- [ ] **Step 6: Commit**

```bash
git add SkillDeck/Sources/SkillDeckCore/AppStore.swift SkillDeck/Tests/SkillDeckCoreTests/AppStoreTests.swift
git commit -m "feat: AppStore coordinator (favorites, recents, search, overrides)"
```

---

## Task 9: AppKit glue — FileWatcher, FrontmostAppTracker, real injection

These touch system APIs and are **not unit-tested**; they are verified manually in Task 11. Keep them small and behind clear interfaces.

**Files:**
- Create: `SkillDeck/Sources/SkillDeckCore/FileWatcher.swift`
- Create: `SkillDeck/Sources/SkillDeckCore/FrontmostAppTracker.swift`
- Modify: `SkillDeck/Sources/SkillDeckCore/Injector.swift`

- [ ] **Step 1: Implement `FileWatcher.swift`**

```swift
import Foundation
import CoreServices

/// Watches directories via FSEvents and calls `onChange` (debounced) on the main queue.
public final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let onChange: () -> Void
    private var debounceWork: DispatchWorkItem?

    public init(paths: [String], onChange: @escaping () -> Void) {
        self.paths = paths
        self.onChange = onChange
    }

    public func start() {
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleDebounced()
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }
        stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            existing as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleDebounced() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Implement `FrontmostAppTracker.swift`**

```swift
import AppKit

/// Tracks the app that was frontmost before SkillDeck took focus, so we can return focus to it.
@MainActor
public final class FrontmostAppTracker {
    public private(set) var previousApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    public init() {}

    public func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            // Ignore ourselves; remember the last *other* app.
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.previousApp = app
            }
        }
    }

    public func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
```

- [ ] **Step 3: Extend `Injector.swift` with real injection**

Add to the existing `Injector` struct (keep `defaultInsertText`):

```swift
import AppKit

extension Injector {
    /// True if the process is trusted for Accessibility (needed to post ⌘V).
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility, opening the System Settings pane.
    public static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    /// Copies `text` to the clipboard, re-activates `target`, and posts ⌘V.
    /// Returns false (copy-only) if Accessibility isn't granted — text is still on the clipboard.
    @MainActor
    @discardableResult
    public static func inject(_ text: String, into target: NSRunningApplication?) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard isAccessibilityTrusted else { return false }
        target?.activate()

        // Give focus a moment to switch, then post Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            postCommandV()
        }
        return true
    }

    @MainActor
    private static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
```

- [ ] **Step 4: Verify it still builds and unit tests pass**

Run: `cd SkillDeck && swift build && swift test`
Expected: build succeeds; all existing tests still PASS (no new tests — these are system APIs verified manually in Task 11)

- [ ] **Step 5: Commit**

```bash
git add SkillDeck/Sources/SkillDeckCore/FileWatcher.swift SkillDeck/Sources/SkillDeckCore/FrontmostAppTracker.swift SkillDeck/Sources/SkillDeckCore/Injector.swift
git commit -m "feat: FSEvents watcher, frontmost-app tracker, clipboard+Cmd-V injection"
```

---

## Task 10: SwiftUI app — window, sidebar, list, detail, menu bar

No unit tests (UI). Build must succeed and the app must launch.

**Files:**
- Create: `SkillDeck/Sources/SkillDeckApp/SkillDeckApp.swift`
- Create: `SkillDeck/Sources/SkillDeckApp/SidebarView.swift`
- Create: `SkillDeck/Sources/SkillDeckApp/ListView.swift`
- Create: `SkillDeck/Sources/SkillDeckApp/DetailView.swift`
- Create: `SkillDeck/Sources/SkillDeckApp/MenuBarView.swift`
- Create: `SkillDeck/Sources/SkillDeckApp/DiagnosticsView.swift`

- [ ] **Step 1: Create `SkillDeckApp.swift` (@main, scenes, wiring)**

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
                ListView(store: store, filter: sidebarFilter, selection: $selection)
            } detail: {
                DetailView(store: store, tracker: tracker, selection: $selection)
            }
            .frame(minWidth: 820, minHeight: 480)
            .onAppear { bootstrap() }
        }

        MenuBarExtra("SkillDeck", systemImage: "command.square") {
            MenuBarView(store: store, tracker: tracker)
        }
        .menuBarExtraStyle(.menu)
    }

    private func bootstrap() {
        tracker.start()
        reload()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let watcher = FileWatcher(
            paths: ["\(home)/.claude/skills", "\(home)/.claude/plugins"],
            onChange: { reload() })
        watcher.start()
        self.watcher = watcher
    }

    private func reload() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projects = ProjectDiscovery.recentProjects(
            historyPath: "\(home)/.claude/history.jsonl", limit: 15)
        let result = Scanner.scanDefault(projectDirs: projects)
        store.setItems(result.items)
        store.setWarnings(result.warnings)
    }
}

enum SidebarFilter: Hashable {
    case all, favorites, recents, commands, skills, plugin(String), diagnostics
}
```

- [ ] **Step 2: Create `SidebarView.swift`**

```swift
import SwiftUI
import SkillDeckCore

struct SidebarView: View {
    let store: AppStore
    @Binding var filter: SidebarFilter

    private var plugins: [String] {
        Array(Set(store.items.compactMap { $0.pluginName })).sorted()
    }

    var body: some View {
        List(selection: Binding(
            get: { filter },
            set: { if let v = $0 { filter = v } })) {
            Section {
                Label("Favorites", systemImage: "star").tag(SidebarFilter.favorites)
                Label("Recent", systemImage: "clock").tag(SidebarFilter.recents)
                Label("All", systemImage: "square.grid.2x2").tag(SidebarFilter.all)
            }
            Section("Type") {
                Label("Commands", systemImage: "terminal").tag(SidebarFilter.commands)
                Label("Skills", systemImage: "sparkles").tag(SidebarFilter.skills)
            }
            Section("Plugins") {
                ForEach(plugins, id: \.self) { p in
                    Label(p, systemImage: "puzzlepiece").tag(SidebarFilter.plugin(p))
                }
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

- [ ] **Step 3: Create `ListView.swift`**

```swift
import SwiftUI
import SkillDeckCore

struct ListView: View {
    let store: AppStore
    let filter: SidebarFilter
    @Binding var selection: String?
    @State private var query: String = ""

    private var rows: [SkillItem] {
        let base: [SkillItem]
        switch filter {
        case .all:        base = store.items
        case .favorites:  base = store.favoriteItems()
        case .recents:    base = store.recentItems(limit: 50)
        case .commands:   base = store.items.filter { $0.kind != .skill }
        case .skills:     base = store.items.filter { $0.kind == .skill }
        case .plugin(let p): base = store.items.filter { $0.pluginName == p }
        case .diagnostics: base = []
        }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            || ($0.pluginName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        Group {
            if case .diagnostics = filter {
                DiagnosticsView(store: store)
            } else {
                List(rows, selection: $selection) { item in
                    HStack {
                        Image(systemName: item.kind == .skill ? "sparkles" : "terminal")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body)
                            Text(item.description).font(.caption)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if store.isFavorite(item.id) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                        }
                    }
                    .tag(item.id)
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search skills & commands")
    }
}
```

- [ ] **Step 4: Create `DetailView.swift`**

```swift
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
                        Text("Accessibility not granted — copied to clipboard. Paste with ⌘V.")
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
        return "\(kind) · \(where_)"
    }
}
```

- [ ] **Step 5: Create `MenuBarView.swift`**

```swift
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
```

- [ ] **Step 6: Create `DiagnosticsView.swift`**

```swift
import SwiftUI
import SkillDeckCore

struct DiagnosticsView: View {
    let store: AppStore
    var body: some View {
        if store.warnings.isEmpty {
            ContentUnavailableView("No issues", systemImage: "checkmark.seal",
                description: Text("All skills and commands parsed cleanly."))
        } else {
            List(Array(store.warnings.enumerated()), id: \.offset) { _, w in
                VStack(alignment: .leading) {
                    Text(w.message).font(.body)
                    Text(w.filePath).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 7: Build and launch**

Run: `cd SkillDeck && swift build`
Expected: build succeeds.
Run: `cd SkillDeck && swift run SkillDeckApp`
Expected: a window opens showing the sidebar + populated list; a menu bar icon appears. (Full behavior verified in Task 11.)

- [ ] **Step 8: Commit**

```bash
git add SkillDeck/Sources/SkillDeckApp
git commit -m "feat: SwiftUI window, sidebar, list, detail, menu bar, diagnostics"
```

---

## Task 11: Manual verification of system behavior

Unit tests can't cover keystroke injection, FSEvents, or focus return. Verify manually.

- [ ] **Step 1: Launch and confirm catalog**

Run: `cd SkillDeck && swift run SkillDeckApp`
Confirm: the list shows real skills (e.g. `wrangler`, `brainstorming`, `code-review`) grouped under the correct plugins; built-ins (`/clear`, `/config`) appear under Commands.

- [ ] **Step 2: Grant Accessibility**

Click "Inject into terminal" once. Expected: a system prompt asks for Accessibility; grant it in System Settings → Privacy & Security → Accessibility, then re-launch.

- [ ] **Step 3: Verify injection into a real terminal**

Open Terminal/iTerm running `claude`. Click a terminal window (so it's frontmost), then click the SkillDeck menu bar icon → click a favorite/recent. Expected: the slash command (e.g. `/code-review`) appears at the terminal prompt, NOT auto-submitted.

- [ ] **Step 4: Verify copy-only fallback**

Revoke Accessibility, click Inject. Expected: orange note "copied to clipboard"; ⌘V pastes the text manually.

- [ ] **Step 5: Verify auto-update**

With the app running, create `~/.claude/skills/zztest/SKILL.md` with `---\nname: zztest\ndescription: temp\n---\nbody`. Expected: `zztest` appears in the list within a few seconds. Then delete it; it disappears.

```bash
mkdir -p ~/.claude/skills/zztest && printf -- '---\nname: zztest\ndescription: temp\n---\nbody\n' > ~/.claude/skills/zztest/SKILL.md
# observe it appear, then:
rm -rf ~/.claude/skills/zztest
```

- [ ] **Step 6: Verify favorites + recents persist across relaunch**

Favorite an item and inject a couple. Quit and relaunch. Expected: favorites still starred; recents still listed.

- [ ] **Step 7: No commit** (manual verification only). If any step reveals a bug, fix via TDD against `SkillDeckCore` where possible, then re-verify.

---

## Task 12: Open-source docs

**Files:**
- Modify: `README.md` (repo root) — or create `SkillDeck/README.md`
- Create: `SkillDeck/CONTRIBUTING.md`

- [ ] **Step 1: Write `SkillDeck/README.md`**

Include: one-line description; screenshot placeholder; **Requirements** (macOS 15+, Swift 6.1 / Xcode 16); **Build & Run** (`cd SkillDeck && swift run SkillDeckApp`); **Permissions** (Accessibility needed for injection, copy-only fallback otherwise); **How it works** (scans `~/.claude` skills/plugins, project `.claude`, built-ins; FSEvents auto-update); **Configuration** (built-in commands editable in `Sources/SkillDeckCore/builtin-commands.json`); **Contributing** link; **License: MIT**.

- [ ] **Step 2: Write `SkillDeck/CONTRIBUTING.md`**

Include: project layout summary (Core library vs App target); how to run tests (`swift test`); the extension points (add a data source in `Scanner.swift`; change injection in `Injector.swift`; add built-ins via `builtin-commands.json`); TDD expectation for `SkillDeckCore` changes.

- [ ] **Step 3: Update repo root `README.md`** to point at `SkillDeck/` and the design/plan docs under `docs/superpowers/`.

- [ ] **Step 4: Commit**

```bash
git add README.md SkillDeck/README.md SkillDeck/CONTRIBUTING.md
git commit -m "docs: README and CONTRIBUTING for SkillDeck"
```

---

## Self-Review

**Spec coverage:**
- Form factor (window + menu bar) → Task 10 ✓
- Swift + SwiftUI → Task 1, 10 ✓
- Insert slash for commands, NL hint for skills, editable → Task 4 (logic), Task 8 (override), Task 10 (UI) ✓
- Injection: clipboard + ⌘V, copy-only fallback, no auto-Enter, focus return → Task 9, 10, 11 ✓
- Data sources: user + plugin + project + built-in → Task 5, 6 ✓
- Real-time auto-update (FSEvents) → Task 9, 10, verified Task 11 ✓
- Favorites/pinning + automatic recents (MRU + count) → Task 8, 10 ✓
- Stable id surviving plugin version bumps → Task 1, 7 ✓
- Diagnostics for parse failures → Task 6 (warnings), Task 10 (view) ✓
- Persistence to Application Support, no caching of scan → Task 7, 8 ✓
- Open-source structure / README / LICENSE / extensibility → Task 1, 12 ✓
- No gaps found.

**Placeholder scan:** No "TBD/TODO/handle edge cases" steps; every code step shows full code. Task 12 docs steps describe content to write (acceptable for prose docs) but name every required section. ✓

**Type consistency:** `SkillItem` initializer signature, `SourceScope.key`, `Injector.defaultInsertText(kind:name:)`, `AppStore` method names (`toggleFavorite`, `recordUse`, `recentItems(limit:)`, `effectiveInsertText(for:)`, `setItems`, `setWarnings`), `PersistedState`/`RecentEntry` fields, `Scanner.scan(...)` / `scanDefault(projectDirs:)`, and `FileWatcher(paths:onChange:)` are used identically across tasks. ✓
