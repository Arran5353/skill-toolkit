# SkillDeck — Design Spec

**Date:** 2026-06-14
**Status:** Approved (pending spec review)

## Summary

SkillDeck is a native macOS application that acts as a live cheatsheet and quick-launcher
for Claude Code skills and slash commands. It auto-discovers everything installed on the
machine (user-level, plugin-provided, project-level, and built-in), presents them in a
searchable, resizable main window, and lets the user click an item to inject its invocation
text into the currently active terminal running Claude Code. A menu bar icon provides quick
access to favorites and recently used items. The catalog updates automatically when skills
or plugins are installed or removed.

The app is built to be open-sourced for the community from day one, including users who may
have hundreds or thousands of skills installed.

## Market Survey (why build this)

No existing free, local tool does this exact combination. Adjacent tools:

- **ClaudeBar / Claude Usage** — menu bar apps that track usage *quotas*, not a cheatsheet.
- **CheatSheet (mac)** — shows an app's *keyboard shortcuts* on holding ⌘; not Claude-aware.
- **MenuBarSSHCommands** — menu bar list of *manually saved* terminal commands; no auto-discovery.
- **Lovcode / browser config UIs** — *management* GUIs for Claude Code config; not a launcher.
- **Built-in `/` menu** — lists commands inside a session only; no window, no recents, no inject-from-outside.

The novel combination — auto-discovered skill/command cheatsheet + full window + menu bar +
click-to-inject into the active terminal + favorites/recents — is not available elsewhere,
which justifies building it.

## Requirements (from brainstorming)

- **Form factor:** Full resizable main window (appears in Dock and ⌘Tab) **plus** a menu bar
  icon for quick access to favorites and recents. Chosen because the catalog can be large
  (hundreds/thousands of skills) and benefits from rich organization; also intended for
  community release.
- **Tech stack:** Swift + SwiftUI (native `MenuBarExtra` + windowed app).
- **What to insert:** Slash command text for commands/built-ins (e.g. `/code-review`);
  natural-language hint for skills (e.g. `use the brainstorming skill`), editable per item.
- **Injection mechanism:** Type into the frontmost app via clipboard + simulated ⌘V
  (CGEvent), with clipboard-copy as automatic fallback. Recommended over AppleScript-to-a-
  named-terminal so it works across Terminal, iTerm, Ghostty, VS Code, etc.
- **Data source scope:** User-level `~/.claude` (skills + commands + plugins) **and**
  project-level `.claude` (current/recent projects) **and** built-in slash commands.
- **Auto-update:** Real-time file watching (FSEvents) — new skills appear within seconds.
- **Recents/favorites:** Manual favorites/pinning **plus** automatic recents (MRU + usage count).
- **Open-source readiness:** Build to publishable open-source standards now (clean structure,
  README, LICENSE, configurable/extensible data sources and injection).

## Architecture

Four independent layers with clear interfaces:

```
UI (SwiftUI)
  Main window: Sidebar (groups) + List (search) + Detail panel
  Menu bar:    MenuBarExtra (favorites + recents)
        │ observes @Observable Store
Store (single source of truth)
  Holds [SkillItem], favorites, recents; coordinates scan/watch/persist
        ├── Scanner       (disk → structured data; stateless; unit-testable)
        ├── FileWatcher   (FSEvents → "directory changed" signal)
        ├── Injector      (send text to frontmost app; CGEvent + clipboard)
        └── Persistence   (read/write JSON state)
```

Each module has a single responsibility so contributors can swap one (e.g. injection
strategy, new data source) without touching the rest.

## Data Model

```swift
enum ItemKind { case skill, command, builtinCommand }

enum SourceScope {
    case user             // ~/.claude/...
    case project(String)  // a project's .claude/, carries project name
    case builtin          // Claude Code built-in
}

struct SkillItem: Identifiable {
    let id: String          // stable key: scope + pluginName + kind + name
    let name: String        // e.g. "brainstorming" / "code-review"
    let kind: ItemKind
    let scope: SourceScope
    let pluginName: String?  // e.g. "superpowers"; nil for top-level/project skills
    let description: String  // from frontmatter `description`
    let body: String         // markdown body (usage/examples) for the detail panel
    let filePath: String?    // source file; nil for built-ins
    let insertText: String   // text injected on click (user-overridable)
}
```

**Stable id is critical:** built from `scope + pluginName + kind + name`, not the file path,
so favorites and usage counts survive a plugin version bump (e.g. `superpowers/5.1.0` →
`6.0.0`, which changes the install directory).

## Scanner Logic

1. **User-level skills:** glob `~/.claude/skills/*/SKILL.md` (top-level, `pluginName = nil`).
2. **Plugin skills + commands:** walk
   `~/.claude/plugins/cache/*/<plugin>/<ver>/skills/*/SKILL.md` and `.../commands/*.md`;
   derive `pluginName` from the path; `scope = .user`.
3. **Project-level:** infer recently opened projects from `~/.claude/history.jsonl` /
   projects directory, then scan each project root's `.claude/skills/` and
   `.claude/commands/`; `scope = .project(name)`.
4. **Built-in commands:** maintained in a repo-tracked `builtin-commands.json`
   (e.g. `/clear`, `/config`, `/review`); `scope = .builtin`.

**Per-file parsing:**
- Split YAML frontmatter → read `name`, `description`; fall back to directory/file name if
  `name` is missing.
- Everything after frontmatter → `body`.
- Tolerant: malformed frontmatter or empty files do not crash; skip and record a warning
  visible in a Diagnostics panel.

**Deduplication / priority:** Same-named items from multiple sources are **not merged** —
each is shown independently with its source scope labeled. This makes it easy to debug
"why are there two brainstorming entries."

**Performance:** Scanning runs on a background thread; results are handed to the Store in one
batch; the list uses SwiftUI lazy loading; search is in-memory fuzzy matching over
name + description + plugin name. Thousands of items are no problem.

## Injection (Injector)

Each `SkillItem` computes `insertText`:
- command / built-in → literal slash, e.g. `/code-review`
- skill → natural-language hint, e.g. `use the brainstorming skill` (editable in the detail panel)

Click-to-inject flow:
1. Write `insertText` to the system clipboard (always — this is the fallback).
2. Re-activate the previously frontmost app (the user's terminal).
3. Simulate ⌘V (CGEvent) → text lands in the terminal input line.
4. Do **not** auto-press Enter — the user confirms and hits Enter manually.

**Why clipboard + simulated ⌘V instead of per-character typing:** per-character CGEvent is
unreliable with IMEs (e.g. Chinese input) and special characters; clipboard + ⌘V is stable
across any terminal and is inherently its own fallback (content is already on the clipboard
if the paste fails).

**Permissions:** Simulating keystrokes requires one-time Accessibility authorization. If not
granted, the app shows a guided prompt + a link to System Settings and **degrades to
copy-only mode** (click copies; user pastes manually) — functionality never blocks.

**Focus handling:** The app continuously tracks the previously frontmost app via
`NSWorkspace.didActivateApplicationNotification`. Before injecting, it re-activates that app,
then sends ⌘V.

## UI / Interaction

```
Main window:
┌──────────┬─────────────────┬──────────────────┐
│ Sidebar   │  List (search)  │  Detail panel     │
│ ★ Favorites│ 🔍 ___________ │ brainstorming    │
│ 🕘 Recent  │ /code-review  ★ │ scope: user/sp   │
│ ─────     │ brainstorming   │ ───────────────  │
│ All        │ systematic-deb… │ description: ...  │
│ Commands   │ ...             │ body (usage): ... │
│ Skills     │                 │ insert text:[edit]│
│ ▸ super…   │                 │ [⤵ Inject][⧉ Copy]│
│ ▸ frontend │                 │ [☆ Favorite]      │
│ ▸ Project X│                 │                  │
└──────────┴─────────────────┴──────────────────┘

Menu bar icon:
  ★ Favorites (click = inject)
  ──────────
  🕘 Recents
  ──────────
  Open main window / Refresh / Quit
```

- **Favorites/recents:** star button pins an item; every injection records to Recents (MRU by
  time) and increments a usage count (kept for future sorting). Both visible in sidebar and
  menu bar.
- **Auto-update:** FileWatcher (FSEvents) watches `~/.claude/skills`, `~/.claude/plugins`, and
  each project's `.claude`; on change, debounce (~500ms) then re-run Scanner; Store updates and
  the UI refreshes — new skills appear within seconds.

## Persistence

User data in `~/Library/Application Support/SkillDeck/state.json` (does not touch `~/.claude`):

```json
{
  "version": 1,
  "favorites": ["user|superpowers|skill|brainstorming"],
  "recents":   [{"id": "...", "lastUsed": "2026-06-14T...", "count": 7}],
  "overrides": {"user|superpowers|skill|brainstorming": "use the brainstorming skill"}
}
```

Only ids and user-generated data are stored. Scan results are **not** cached — scanning is
fast enough to re-run on every launch, guaranteeing freshness and avoiding cache-invalidation bugs.

## Project Structure (open-source)

```
SkillDeck/
├── README.md            # screenshots, install, permissions, contributing
├── LICENSE              # MIT
├── CONTRIBUTING.md
├── builtin-commands.json # built-in command list (community-maintainable via PR)
├── SkillDeck.xcodeproj
├── Sources/
│   ├── App/             # SkillDeckApp, main window, MenuBarExtra
│   ├── Models/          # SkillItem, SourceScope, ItemKind
│   ├── Core/
│   │   ├── Scanner.swift
│   │   ├── FrontmatterParser.swift
│   │   ├── FileWatcher.swift
│   │   ├── Injector.swift
│   │   └── Persistence.swift
│   ├── Store/           # AppStore (@Observable)
│   └── Views/           # SidebarView, ListView, DetailView, MenuBarView
└── Tests/
    └── SkillDeckTests/  # pure-logic unit tests
```

**Extension points for the community:** data sources (Scanner paths), injection strategy
(Injector protocol), and the built-in command list are replaceable/configurable; adding a new
data source touches a single file.

## Testing Strategy (TDD, pure-logic first)

- **FrontmatterParser:** normal / missing name / malformed YAML / empty file, via fixture files.
- **Scanner:** given a temp directory tree, assert item count, scope, pluginName, and id.
- **Persistence:** save→load round-trip equality; favorites survive a plugin path change
  (via stable id).
- **Injector:** the `insertText` generation logic is unit-tested; actual CGEvent injection is
  verified manually (system keystrokes can't be unit-tested).

## Error Handling

- A single file failing to parse never affects the whole catalog — skip + collect into a
  Diagnostics panel (visible from the menu) so the user knows which skill wasn't recognized and why.
- Missing Accessibility permission → automatic degrade to copy-only mode.
- File-watching failure → fall back to "scan on launch + manual refresh".
