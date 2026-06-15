# SkillDeck v2 — Marketplace Browser & One-Click Install — Design Spec

**Date:** 2026-06-15
**Status:** Approved (pending spec review)
**Builds on:** [v1 design](2026-06-14-skilldeck-design.md) and its [plan](../plans/2026-06-14-skilldeck.md)

## Summary

v2 upgrades SkillDeck from an "installed cheatsheet" into a layered **browser + one-click
installer**. It keeps every v1 capability (inject, favorites, recents, FSEvents auto-update)
and adds: a **Marketplace → Plugin → Skill/Command** three-level hierarchy, and the ability
to click an uninstalled plugin to install it in the background via `claude plugin install`.

This is an evolution of v1, not a rewrite. v1's `SkillItem` folds into a unified `Node`
model; Scanner / Injector / AppStore / persistence are reused. New pieces: a marketplace data
source, an installer, a tree builder, and tree/marketplace UI.

## Context: the real hierarchy on disk (verified)

Claude Code plugins flow from cloud git repos through a local "shelf" to "installed":

```
cloud git repo (GitHub)
   │  claude clones/pulls the catalog
   ▼
~/.claude/plugins/marketplaces/<mp>/.claude-plugin/marketplace.json   ← the shelf (what CAN be installed)
   │  user installs a plugin
   ▼
~/.claude/plugins/cache/<mp>/<plugin>/<ver>/                          ← installed (skills/commands present on disk)
```

Key facts established during design:
- A **marketplace** is a registered source (a git repo). The user has 3 registered:
  `claude-plugins-official` (Anthropic, ~363 plugins), `impeccable` (3rd-party, ~4),
  `ui-ux-pro-max-skill` (3rd-party, ~4). Anyone can publish a marketplace; not just Anthropic.
- `marketplace.json` has a `plugins[]` array: each entry has `name`, `description`,
  `source`, etc. This is the catalog of installable plugins.
- An **uninstalled** plugin can only be shown at **plugin granularity** — its internal
  `SKILL.md` / `commands/*.md` are still in the cloud and not on disk. Only after install do
  its skills/commands become visible (like the App Store: you see the app description before
  download, its features after).
- `claude plugin install <plugin>@<marketplace>` is the supported CLI to install.
  `installed_plugins.json` lists what's installed (keys like `superpowers@claude-plugins-official`).

The full tree is a three-level trunk plus three side branches that do NOT hang under any
marketplace:

```
Sources
├── Marketplaces
│     ├── claude-plugins-official (official, ~363 plugins)
│     │     ├── superpowers   [installed] ▸ skills: brainstorming, tdd…
│     │     ├── ralph-loop    [available] ▸ [Install]
│     │     └── … (~360 more, available)
│     ├── impeccable / ui-ux-pro-max-skill (3rd-party)
├── My local skills      (~/.claude/skills/ — user-placed, not from any plugin)
├── Project skills/commands (a project's .claude/)
└── Built-in commands    (Claude Code's own slash commands)
```

Note: the user's 9 top-level skills (cloudflare, wrangler, durable-objects, …) are
**user-placed local skills**, not Claude Code built-ins. Claude Code ships no skills — only
the slash commands are built in.

## Requirements (from brainstorming)

- **Install execution:** the app runs `claude plugin install <plugin>@<marketplace>` itself in
  the background; FSEvents auto-rescan flips status to installed when `cache/` changes.
- **Unified data model:** one `Node` type with `kind` + `status` fields, parent/child tree.
- **Default view:** show only installed (the high-frequency "look up usage" case); marketplace
  browsing is a separate entry, not mixed into the default list.
- **Granularity limitation accepted:** uninstalled plugins shown at plugin granularity;
  install reveals internal skills/commands.
- **Install feedback:** inline status (spinner → ✓ / ✗) on the plugin row; auto-refresh on success.
- **v1 reuse:** evolve — fold `SkillItem` into `Node`, keep Scanner/Injector/AppStore/persistence,
  add marketplace source + installer + tree UI. No rewrite.

## Data Model

```swift
enum NodeKind { case marketplace, plugin, skill, command, builtinCommand, localSkill }
enum InstallStatus { case installed, available, notApplicable }  // leaves/local/builtin = notApplicable

struct Node: Identifiable, Equatable, Sendable {
    let id: String              // stable, path-free (see below)
    let kind: NodeKind
    let name: String
    let description: String
    let status: InstallStatus
    let parentID: String?       // builds the tree: skill.parent = plugin, plugin.parent = marketplace

    // leaf-only (skill/command/localSkill/builtinCommand):
    let body: String?
    let insertText: String?
    let filePath: String?

    // plugin-only:
    let marketplaceName: String?
    let installRef: String?     // "<plugin>@<marketplace>" for claude plugin install
}
```

**Stable id rules** (preserve v1's path-free approach so favorites/recents survive):
- marketplace: `mp|<name>`
- plugin: `mp|<marketplace>|plugin|<name>`
- installed leaf: v1 format `<scopeKey>|<plugin-or-_>|<kind>|<name>` (so v1 favorites/recents keep matching)

## Data Sources & Scanning

Two new sources beside the existing v1 Scanner; a TreeBuilder assembles everything.

**A. MarketplaceScanner (new)** — reads `~/.claude/plugins/marketplaces/*/.claude-plugin/marketplace.json`:
- each file → one `marketplace` node (name from manifest `name`).
- its `plugins[]` → one `plugin` node each; `parentID` = the marketplace node id;
  `installRef = "<plugin>@<marketplace>"`; description from manifest.
- **status**: check against the installed set (from `installed_plugins.json`) — hit →
  `.installed`, else `.available`.

**B. InstalledPluginsIndex (new)** — parses `installed_plugins.json` → `Set<String>` of
installed `plugin@marketplace` keys, used for status decisions.

**Installed-plugin leaves (reuse v1 Scanner):** v1 already scans
`plugins/cache/<mp>/<plugin>/<ver>/skills|commands`. v2 sets those leaf nodes' `parentID` to
the corresponding plugin node (`mp|<marketplace>|plugin|<pluginName>`) so they hang on the
tree. **Uninstalled plugins have no leaves** — the plugin node is expandable but shows
"internal skills/commands visible after install".

**Three side branches (reuse v1 Scanner, ~unchanged):** local skills (`~/.claude/skills/`),
project skills/commands, built-in commands — each hangs under its own side-branch root.

**TreeBuilder (new):** connects all scan outputs by `parentID` into a tree, deduping by id
(reusing v1's multi-version dedupe logic). Scanners stay decoupled; TreeBuilder only wires
edges + dedupes.

**Performance (363+ nodes):** each marketplace manifest is a single JSON file (the 363 plugins
are array items, not 363 files); scanning runs on a background thread; UI uses lazy loading +
collapse, marketplaces collapsed by default.

**Tolerance:** a corrupt marketplace.json → skip + a ScanWarning (reuse v1 mechanism); other
sources unaffected.

## Installer (new)

```swift
@MainActor
final class Installer {
    enum State: Equatable { case idle, installing, succeeded, failed(String) }
    private(set) var states: [String: State] = [:]   // keyed by plugin node id
    func install(_ node: Node) async                 // runs claude plugin install <installRef>
}
```

- Runs `claude plugin install <plugin>@<marketplace>` via `Process` in the background.
  Locate `claude`: search PATH, fall back to `~/.local/bin/claude` (where it is on this machine).
- During run: `states[id] = .installing` (inline spinner); exit 0 → `.succeeded`,
  non-zero → `.failed(stderr summary)`.
- **No manual refresh on success:** v1's FileWatcher already watches `plugins/`; a new plugin
  in `cache/` → auto-rescan → the plugin's status becomes `.installed` and its skills expand.
  The Installer does not mutate the tree — it only runs the command and reports state; the tree
  is rebuilt by Scanner (single responsibility).
- The command construction (installRef → argument array) is extracted as a pure function for
  unit testing; actual `Process` execution is verified manually.
- Uninstall (`claude plugin uninstall`) is out of scope for v2 (YAGNI) — left as a small follow-up.

## UI (extends v1's three-pane layout)

```
┌──────────────┬────────────────────────┬─────────────────┐
│ Sidebar       │  List/Tree (searchable)│  Detail panel    │
│ ★ Favorites   │ 🔍 ____________        │  brainstorming  │
│ 🕘 Recent     │ ▾ superpowers [inst]   │  source: super..│
│ ── Sources ── │     brainstorming      │  usage...        │
│ All(installed)│     tdd                │  [⤵ Inject][⧉][☆]│
│ Commands      │ ▸ frontend-design[inst]│                 │
│ Skills        │ ── My local skills ──  │  (plugin node:)  │
│ My local      │   cloudflare           │  ralph-loop      │
│ Built-in      │   wrangler             │  Not installed   │
│ ── Browse ──  │ (Marketplace mode:)    │  [⬇ Install] ⟳…  │
│ 🛒 Marketplace│   marketplace → plugin │                 │
└──────────────┴────────────────────────┴─────────────────┘
```

- **Default view (installed):** like v1, but installed-plugin skills now hang under a
  collapsible plugin node (`DisclosureGroup`). Side branches (local/project/built-in) are groups.
- **Marketplace mode:** sidebar `🛒 Marketplace` → list switches to a marketplace→plugin tree
  with search. Installed plugins marked ✓ and expandable; uninstalled show an `[Install]` button
  → Installer runs, inline spinner / ✓ / ✗.
- **Detail panel:** leaf node → v1's inject/favorite UI; plugin node → plugin description +
  install/uninstall button + status.
- **New view files:** `TreeListView` (collapsible tree), `MarketplaceView` (browse mode),
  `PluginDetailView` (plugin detail w/ install). v1's ListView/DetailView reused for leaves.

**Error handling:** `claude` not found → install button disabled + "claude CLI not found" note;
install failure → inline red summary + stderr visible in the detail panel.

## AppStore Changes (evolve, not rewrite)

- `items: [SkillItem]` → `nodes: [Node]`. v1's favorites/recents/overrides logic is unchanged
  (still id-based; installed-leaf ids keep the v1 format → seamless migration).
- New: `children(of parentID:) -> [Node]`, `rootNodes(scope:)`, holds an `Installer`.
- search extends to nodes (installed leaves + plugin name/description).
- Favorites/recents are **leaf-only** (plugin/marketplace nodes not favoritable) — a simple
  constraint that avoids semantic confusion.

**v1→v2 migration:** state.json structure is unchanged (favorites/recents/overrides are id
string lists). Because installed-leaf ids keep the v1 format, existing users' favorites/recents
keep working with no migration code.

## Project Structure (incremental additions to SkillDeckCore)

```
Sources/SkillDeckCore/
├── Models/Node.swift              (new: Node, NodeKind, InstallStatus)
├── Models/SkillItem.swift         (kept; Scanner may use internally, mapped to Node)
├── MarketplaceScanner.swift       (new)
├── InstalledPluginsIndex.swift    (new)
├── TreeBuilder.swift              (new: assemble by parentID + dedupe)
├── Installer.swift                (new)
├── Scanner.swift / FrontmatterParser.swift / ... (kept)
└── AppStore.swift                 (changed: nodes + tree traversal + Installer)
Sources/SkillDeckApp/
├── TreeListView.swift / MarketplaceView.swift / PluginDetailView.swift (new)
└── (v1 views reused for leaves)
```

## Testing Strategy (TDD, pure-logic first)

- **MarketplaceScanner:** given a temp marketplace.json, assert plugin node count, name,
  installRef, status (against an installed index).
- **InstalledPluginsIndex:** parse installed_plugins.json → correct `plugin@mp` set.
- **TreeBuilder:** given flat nodes, assert tree shape (children relations, multi-version dedupe,
  orphan-node tolerance).
- **Node id generation + v1 leaf-id compatibility:** an old favorite id still matches a node.
- **Installer:** command construction (installRef → arg array) as a pure unit-tested function;
  real `Process` execution verified manually.
- Reuse all existing v1 tests (must keep passing).

## Manual Verification (folded into the v1 Task 11)

Install a real uninstalled plugin (e.g. `ralph-loop`) → see inline spinner → on success it
appears in the installed tree, expandable; marketplace search; side branches render correctly.
Plus the v1 manual checks (injection, Accessibility fallback, FSEvents auto-update, persistence).
