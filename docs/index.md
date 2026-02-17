---
title: Home
nav_order: 1
---

# tmux-dispatch

A unified command palette for tmux — files, grep, git, directories, and sessions in one popup.

![tmux-dispatch demo](https://raw.githubusercontent.com/ZviBaratz/tmux-dispatch/main/assets/demo.gif)

---

## Modes

tmux-dispatch provides six modes, all accessible from a single popup:

| Mode | Prefix | Description |
|------|--------|-------------|
| [File Finder](modes/files) | _(home)_ | Fuzzy file search with bat preview |
| [Live Grep](modes/grep) | `>` | Ripgrep reloads on every keystroke |
| [Git Status](modes/git) | `!` | Stage/unstage with colored status icons |
| [Directories](modes/dirs) | `#` | Jump to directories via zoxide |
| [Sessions](modes/sessions) | `@` | Switch, create, or kill tmux sessions |
| [Windows](modes/windows) | _(from sessions)_ | Browse windows with pane preview |

## Features

- [Mode Switching](features/mode-switching) — Type prefixes to switch modes, backspace to return home
- [Bookmarks & Frecency](features/bookmarks) — Pin files and rank by recent/frequent usage
- [Preview System](features/previews) — Syntax-highlighted previews across all modes

## Quick Links

- [Getting Started](getting-started) — Install and configure in 2 minutes
- [Keybindings Reference](reference/keybindings) — Every keybinding in one place
- [Configuration](reference/configuration) — All `@dispatch-*` options
- [Troubleshooting](reference/troubleshooting) — Common issues and fixes
- [Architecture](reference/architecture) — How the scripts fit together
