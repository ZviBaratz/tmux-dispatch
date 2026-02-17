---
title: Modes
nav_order: 3
has_children: true
---

# Modes

tmux-dispatch provides six modes, all accessible from a single popup. Files is the home mode -- type a prefix character to switch to another mode, and backspace on an empty query returns home. See [Mode Switching](../features/mode-switching) for details on how prefix-based navigation works.

| Mode | Prefix | Description |
|------|--------|-------------|
| [File Finder](files) | _(home)_ | Fuzzy file search with bat preview, bookmarks, frecency ranking, and git status indicators |
| [Live Grep](grep) | `>` | Ripgrep reloads on every keystroke with line-highlighted preview |
| [Git Status](git) | `!` | Stage/unstage files with `Tab`, colored status icons, inline diff preview |
| [Directories](dirs) | `#` | Jump to directories via zoxide frecency or fd/find fallback |
| [Sessions](sessions) | `@` | Switch, create, rename, or kill tmux sessions with window grid preview |
| [Windows](windows) | _(from sessions)_ | Browse windows within a session using 2D grid navigation with pane content preview |
