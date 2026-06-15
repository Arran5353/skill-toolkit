# SkillDeck

A native macOS app that turns your installed Claude Code skills and commands into a
searchable cheatsheet — and a one-click browser for everything you *could* install.

Forget what a skill does or how a command is invoked? Open SkillDeck, find it, click, and the
invocation is sent straight to your active terminal. New skills and plugins appear
automatically as you install them.

> Screenshot placeholder — add `docs/screenshot.png`.

## Features

- **Installed cheatsheet.** Browse every skill and command you have installed, grouped by
  plugin, plus your own local skills (`~/.claude/skills/`), project skills/commands, and
  Claude Code's built-in slash commands.
- **Click to inject.** Clicking an item copies its invocation (`/code-review`, or
  `use the brainstorming skill`) and pastes it into the frontmost terminal via ⌘V. Works with
  any terminal (Terminal, iTerm, Ghostty, VS Code). No auto-Enter — you confirm.
- **Marketplace browser.** Browse plugins available from your registered marketplaces, see
  which are installed, and install an uninstalled plugin with one click
  (`claude plugin install <plugin>@<marketplace>`). Its skills appear automatically once installed.
- **Favorites & recents.** Star the items you use most; recently injected items float to the top.
- **Menu bar access.** A menu bar icon gives quick access to favorites and recents.
- **Auto-update.** A file watcher (FSEvents) rescans when you install/remove skills or plugins,
  so the catalog is always current.

## Requirements

- macOS 15+
- Swift 6.1 / Xcode 16 (to build)
- The `claude` CLI on your PATH or at `~/.local/bin/claude` (for marketplace install)

## Build & Run

```bash
cd SkillDeck
swift run SkillDeckApp
```

This launches the app (a window plus a menu bar icon). To produce a standalone `.app` bundle,
wrap the built executable with your preferred bundling step; SwiftPM builds the executable at
`.build/debug/SkillDeckApp`.

## Permissions

Injecting into the terminal simulates a ⌘V keystroke, which requires **Accessibility**
permission (System Settings → Privacy & Security → Accessibility). The first time you inject,
SkillDeck prompts for it. Until granted, SkillDeck falls back to **copy-only** mode: clicking
copies the invocation to the clipboard and you paste it yourself. Functionality never blocks.

## How it works

SkillDeck scans, with no caching (always fresh on launch + on file changes):

- `~/.claude/skills/` — your local skills
- `~/.claude/plugins/cache/` — installed plugins' skills and commands
- `~/.claude/plugins/marketplaces/*/.claude-plugin/marketplace.json` — available plugins
- recent projects (from `~/.claude/history.jsonl`) — their `.claude/` skills and commands
- a bundled list of Claude Code built-in slash commands

Everything is assembled into a Marketplace → Plugin → Skill/Command tree, with local skills,
project items, and built-ins as separate top-level groups. Install status is derived by
comparing the marketplace catalog against `~/.claude/plugins/installed_plugins.json`.

User data (favorites, recents, custom insert-text overrides) is stored separately in
`~/Library/Application Support/SkillDeck/state.json` and never touches `~/.claude`.

## Configuration

The built-in slash command list lives in
`Sources/SkillDeckCore/builtin-commands.json` — community PRs welcome.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
