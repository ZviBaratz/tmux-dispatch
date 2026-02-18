---
title: Configuration
parent: Reference
nav_order: 2
---

# Configuration

All tmux-dispatch options are set via tmux options in your `~/.tmux.conf`. Every option uses the `@dispatch-` prefix and has sensible defaults, so the plugin works out of the box with no configuration required.

## Keybinding options

Customize which keys open each mode. Set any key option to `"none"` to disable that keybinding entirely -- the plugin will skip registering it, so there is no conflict with other plugins or tmux bindings.

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-find-key` | `M-o` | Prefix-free key to open file finder (Alt+o) |
| `@dispatch-grep-key` | `M-s` | Prefix-free key to open live grep (Alt+s) |
| `@dispatch-session-key` | `M-w` | Prefix-free key to open session picker (Alt+w) |
| `@dispatch-git-key` | `none` | Prefix-free key to open git status (disabled by default; use `!` prefix instead) |
| `@dispatch-prefix-key` | `e` | Prefix key to open file finder (prefix+e) |
| `@dispatch-session-prefix-key` | `none` | Prefix key to open session picker (disabled by default) |
| `@dispatch-resume-key` | `none` | Prefix-free key to reopen last-used mode with last query (disabled by default) |

## Popup options

Control the popup dimensions and which editors are used.

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-popup-size` | `85%` | Width **and** height of the popup window (the same value is used for both dimensions) |
| `@dispatch-popup-editor` | auto-detect | Editor used inside the popup. Auto-detection order: nvim, vim, vi |
| `@dispatch-pane-editor` | auto-detect | Editor used for Ctrl+O send-to-pane. Uses `$EDITOR` if set, otherwise auto-detects (nvim, vim, vi) |

The popup editor must be a terminal editor (vim, nvim, vi) since it runs inside the popup. The pane editor can be anything, including GUI editors like VS Code or Cursor.

**Note on tilde expansion:** tmux option values are passed as literal strings. If you use `~` in a path (e.g., in `@dispatch-session-dirs`), be aware that tilde expansion depends on how the value is evaluated. Use `$HOME` instead of `~` for reliable path expansion in tmux options.

## Search tool options

Pass extra arguments to the underlying search tools.

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-fd-args` | `""` | Extra arguments passed to `fd` (e.g., `"--max-depth 8"`, `"--hidden"`) |
| `@dispatch-rg-args` | `""` | Extra arguments passed to `rg` (e.g., `"--glob '!*.min.js'"`, `"--hidden"`) |

## Feature toggles

Enable or disable optional features.

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-history` | `on` | Track recently opened files and rank them higher in file finder (frecency) |
| `@dispatch-git-indicators` | `on` | Show colored status icons (modified/staged/untracked) next to files in file finder |

## Appearance

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-theme` | `default` | Color theme. Set to `"none"` to disable built-in colors and inherit from terminal or `FZF_DEFAULT_OPTS` |

## File type filter

Restrict the file finder to specific file extensions.

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-file-types` | `""` | Comma-separated list of extensions to include (e.g., `"ts,tsx,js"`). Empty string shows all files |

When set, only files matching the listed extensions appear in the file finder, bookmarks, and frecency results.

## Scrollback options

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-scrollback-lines` | `10000` | Number of scrollback lines to capture from the originating pane |

## Commands options

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-commands-file` | `~/.config/tmux-dispatch/commands.conf` | Path to the custom commands configuration file |

## Session directories

Configure which directories are scanned for the Ctrl+N project launcher in session mode.

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-session-dirs` | `$HOME/Projects` | Colon-separated list of directories to scan for project directories |

Each path in the list is scanned for immediate subdirectories, which are presented as candidates for new tmux sessions. For example, if you have `~/Projects/app` and `~/Projects/api`, both appear as session creation options.

## Example configuration

A complete example showing all available options:

```tmux
# Keybindings
set -g @dispatch-find-key "M-o"
set -g @dispatch-grep-key "M-s"
set -g @dispatch-session-key "M-w"
set -g @dispatch-git-key "none"
set -g @dispatch-prefix-key "e"
set -g @dispatch-session-prefix-key "none"
set -g @dispatch-resume-key "M-r"

# Popup
set -g @dispatch-popup-size "85%"
set -g @dispatch-popup-editor "nvim"
set -g @dispatch-pane-editor "code"

# Search tools
set -g @dispatch-fd-args "--max-depth 8"
set -g @dispatch-rg-args "--glob '!*.min.js'"

# Features
set -g @dispatch-history "on"
set -g @dispatch-git-indicators "on"

# Appearance (set to "none" to use terminal colors)
set -g @dispatch-theme "default"

# File type filter
set -g @dispatch-file-types "ts,tsx,js"

# Scrollback
set -g @dispatch-scrollback-lines "10000"

# Commands
set -g @dispatch-commands-file "$HOME/.config/tmux-dispatch/commands.conf"

# Session directories
set -g @dispatch-session-dirs "$HOME/Projects:$HOME/work"
```
