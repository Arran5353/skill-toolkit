# Contributing to SkillDeck

Thanks for your interest! SkillDeck is a small, focused codebase designed to be easy to extend.

## Project layout

```
Sources/
├── SkillDeckCore/   # all logic — pure, testable, no SwiftUI
│   ├── Models/       # Node (the unified tree node), SkillItem, Diagnostics
│   ├── Scanner.swift / MarketplaceScanner.swift / ProjectDiscovery.swift
│   │                 #   InstalledPluginsIndex.swift  — data sources
│   ├── FrontmatterParser.swift / BuiltinCommands.swift
│   ├── TreeBuilder.swift        # assembles scan results into the node tree
│   ├── CatalogLoader.swift      # combines all scanners → final tree
│   ├── Injector.swift           # insert-text derivation + clipboard/⌘V
│   ├── Installer.swift          # claude plugin install (Process)
│   ├── FileWatcher.swift / FrontmostAppTracker.swift / Persistence.swift
│   └── AppStore.swift           # @Observable single source of truth
└── SkillDeckApp/    # SwiftUI views only (@main, window, menu bar)
Tests/
└── SkillDeckCoreTests/   # unit tests for everything in Core
```

The split is deliberate: **all logic lives in `SkillDeckCore`** so it can be unit-tested
without a UI. `SkillDeckApp` holds only SwiftUI views and the `@main` entry point.

## Running tests

```bash
cd SkillDeck
swift test
```

Core changes must be test-driven — write a failing test first, then the implementation. The
existing tests use temporary directory trees (no fixtures checked in) and real round-trips
(no mocking of `FileManager`); follow that pattern.

UI views in `SkillDeckApp` are not unit-tested; verify them by running the app
(`swift run SkillDeckApp`) and checking behavior manually.

## Extension points

The architecture is built so most additions touch a single file:

- **Add a data source** (e.g. a new place skills live): write a new scanner in `SkillDeckCore`
  that returns `[Node]` (or `[SkillItem]` mapped via `TreeBuilder`), then wire it into
  `CatalogLoader.load`.
- **Change how invocations are inserted**: `Injector.defaultInsertText` (per-kind text) and
  `Injector.inject` (the paste mechanism).
- **Change how plugins install**: `Installer` (it shells out to `claude plugin install`).
- **Add/edit built-in commands**: `Sources/SkillDeckCore/builtin-commands.json`.

## Known limitations

- Cross-marketplace plugin name collisions: if two marketplaces ever ship a plugin with the
  same name, an installed plugin's skills may be grouped under the wrong marketplace in the
  tree (the skill and its injection stay correct). See the note in `TreeBuilder.swift`.
- Uninstall is not yet implemented — only install.

## Conventions

- Keep files focused on one responsibility.
- Match the surrounding code's naming and style.
- Swift 6 strict concurrency is on; prefer `@MainActor` for UI-facing state and value types
  for `Sendable` data.
