---
title: Architecture
parent: Reference
nav_order: 3
---

# Architecture

tmux-dispatch is built as a single-script-with-modes design: one main script (`dispatch.sh`) handles all modes via a `--mode` flag, and fzf's `become` action enables seamless mode switching without restarting the popup. There is no build step -- the plugin is seven shell scripts that are sourced or executed directly.

## Mode tree

The plugin operates as a mode tree rooted at the files (home) mode. Prefix characters switch into sub-modes, and backspace on an empty query returns to home, similar to VS Code's command palette.

```
dispatch.sh --mode=files  (home mode, prompt: "  ")
  +-- fd | fzf (filtering, bookmarks, git indicators, frecency ranking)
  |   +-- ">" prefix --> become(dispatch.sh --mode=grep --query={q})
  |   +-- "@" prefix --> become(dispatch.sh --mode=sessions --query={q})
  |   +-- "!" prefix --> become(dispatch.sh --mode=git --query={q})
  |   +-- "#" prefix --> become(dispatch.sh --mode=dirs --query={q})
  |   +-- Ctrl+R --> become(dispatch.sh --mode=rename)
  |
dispatch.sh --mode=grep  (prompt: "> ")
  +-- fzf --disabled + change:reload:rg (live search)
  |   +-- backspace on empty --> become(dispatch.sh --mode=files)
  |
dispatch.sh --mode=git  (prompt: "! ")
  +-- git status --porcelain | fzf (stage/unstage with Tab, diff preview)
  |   +-- backspace on empty --> become(dispatch.sh --mode=files)
  |
dispatch.sh --mode=dirs  (prompt: "# ")
  +-- zoxide/fd/find directories | fzf (tree preview, cd on Enter)
  |   +-- backspace on empty --> become(dispatch.sh --mode=files)
  |
dispatch.sh --mode=sessions  (prompt: "@ ")
  +-- tmux list-sessions | fzf (session picker + creator)
  |   +-- backspace on empty --> become(dispatch.sh --mode=files)
  |   +-- Ctrl+N --> become(dispatch.sh --mode=session-new)
  |   +-- Ctrl+W --> become(dispatch.sh --mode=windows --session={1})
  |   +-- Ctrl+R --> become(dispatch.sh --mode=rename-session)
  |
dispatch.sh --mode=windows
  +-- tmux list-windows | fzf (2D grid navigation with arrow keys)
  |   +-- backspace on empty --> become(dispatch.sh --mode=sessions)
  |
dispatch.sh --mode=session-new
  +-- fd directories | fzf (project directory picker)
  |   +-- backspace on empty --> become(dispatch.sh --mode=sessions)
  |
dispatch.sh --mode=rename
  +-- fzf query as new filename (inline rename for selected files)
  |
dispatch.sh --mode=rename-session
  +-- fzf query as new session name (inline rename for selected session)
```

## Script roles

The plugin consists of seven scripts, each with a focused responsibility.

### dispatch.tmux

The TPM entry point. Reads all `@dispatch-*` tmux options and registers keybindings accordingly. Detects the tmux version to decide between `display-popup` (tmux 3.2+) and the `split-window` fallback for older versions. This script does not use `set -euo pipefail` because TPM entry points must not exit on error.

### scripts/helpers.sh

Sourced by all other scripts. Provides shared utility functions:

- **`get_tmux_option`** -- Reads tmux options with fallback defaults
- **Tool detection** -- `detect_fd`, `detect_bat`, `detect_rg`, `detect_zoxide`, `detect_popup_editor`, `detect_pane_editor`. Handles Debian/Ubuntu renamed binaries (`fdfind`, `batcat`)
- **fzf visual options** -- Consistent styling (colors, borders, layout) across all modes
- **File history and frecency** -- Per-directory tracking of recently and frequently opened files
- **Bookmarks** -- Persistent file bookmarks with starred indicators

This script omits `set -euo pipefail` because it is sourced into other scripts' environments.

### scripts/dispatch.sh

The main script. Accepts a `--mode` flag with nine possible values: `files`, `grep`, `git`, `dirs`, `sessions`, `session-new`, `windows`, `rename`, and `rename-session`. Each mode configures fzf differently (prompt, preview command, keybindings, reload behavior). Uses fzf's `become` action to re-execute itself with a different mode, enabling seamless mode switching within a single popup.

### scripts/actions.sh

Extracted action handlers called by fzf key bindings. Includes:

- File edit (popup and send-to-pane)
- Grep edit (with line number positioning)
- File delete and rename
- Bookmark toggle
- Git stage/unstage
- Session list, switch, and rename
- Preview helper functions

### scripts/preview.sh

Preview command for grep mode. Displays file content with the matching line highlighted using `bat` (with `--highlight-line`). Falls back to `head` when `bat` is not available.

### scripts/git-preview.sh

Preview command for git status mode. Shows the diff for the selected file. Handles staged changes, unstaged changes, and combined diffs depending on the file's git status.

### scripts/session-preview.sh

Preview command for both session mode and window mode. Renders a 2-column grid of windows belonging to the selected session. Each window cell shows a pane content snapshot captured via `tmux capture-pane`. Uses Perl for ANSI-aware width handling to properly truncate and pad content within the box-drawing grid. Accepts an optional second argument (window index) to highlight the fzf-selected window with bright cyan borders in window mode.

## Design principles

**Graceful fallbacks.** Every optional tool has a fallback path. `fd` falls back to `find`, `bat` falls back to `head`, `zoxide` falls back to `fd`/`find` for directories. The plugin works (with reduced features) on minimal systems.

**No build step.** The plugin is pure bash -- no compilation, transpilation, or bundling. Install via TPM or clone and source.

**Bash 4.0+ required.** The scripts use associative arrays and other bash 4.0 features. macOS users need to install a modern bash via Homebrew (`brew install bash`) since the system `/bin/bash` is version 3.2.
