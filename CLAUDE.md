# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

tmux-dispatch is a tmux plugin (installed via TPM) that provides a unified command palette for tmux — fuzzy file finding, live grep, git status, directory jump, session/window management — all in one popup. Written entirely in bash.

## Commands

### Lint (matches CI)
```bash
shellcheck -x -e SC1091 dispatch.tmux scripts/*.sh
```

### Syntax check
```bash
bash -n dispatch.tmux && bash -n scripts/helpers.sh && bash -n scripts/dispatch.sh && bash -n scripts/preview.sh && bash -n scripts/actions.sh && bash -n scripts/git-preview.sh && bash -n scripts/session-preview.sh
```

### Unit tests
```bash
bats tests/
```
Requires [bats-core](https://github.com/bats-core/bats-core). Five test files cover helpers (tool detection, version comparison), dispatch (arg parsing, mode switching, security validation, transform/mapfile tests), actions (rename, delete, git toggle, session kill, edit), history (frecency, bookmarks), and previews.

### Manual testing
Requires a running tmux session. Reload the plugin with:
```bash
tmux source-file ~/.tmux.conf
```

## Architecture

Seven shell scripts, no build step:

- **`dispatch.tmux`** — TPM entry point. Reads `@dispatch-*` tmux options and registers keybindings. Detects tmux version to choose between `display-popup` (3.2+) and `split-window` fallback.
- **`scripts/helpers.sh`** — Sourced by all other scripts. Provides `get_tmux_option`, tool detection (`detect_fd`, `detect_bat`, `detect_rg`, `detect_zoxide`, `detect_popup_editor`, `detect_pane_editor`), file history/frecency, bookmarks, and fzf visual options. Handles Debian/Ubuntu renamed binaries (e.g., `fdfind`, `batcat`).
- **`scripts/dispatch.sh`** — Main script with nine modes via `--mode=files|grep|git|dirs|sessions|session-new|windows|rename|rename-session`. Uses fzf's `become` action to switch modes mid-session. Handles mode-specific fzf configuration, indicators (bookmarks ★, git status icons), and result actions.
- **`scripts/actions.sh`** — Extracted action handlers called by fzf bindings: file edit, grep edit, delete, rename, bookmark toggle, git stage/unstage, session list/rename/kill, and preview helpers.
- **`scripts/preview.sh`** — Preview command for grep mode. Shows file content with line highlighting via bat (or head fallback).
- **`scripts/git-preview.sh`** — Preview command for git mode. Shows `git diff` for changed files; handles renamed files (`old -> new` format).
- **`scripts/session-preview.sh`** — Preview command for session and window modes. Shows window layout grid with pane content; accepts optional highlight parameter for window mode.

## Conventions

- Requires bash 4.0+ (`dispatch.sh` and `session-preview.sh` enforce this with a version guard). macOS ships bash 3.2 — users need `brew install bash`.
- All scripts use `#!/usr/bin/env bash`; all scripts except `dispatch.tmux` and `helpers.sh` use `set -euo pipefail` (`dispatch.tmux` omits it as a TPM entry point; `helpers.sh` omits it because it's sourced)
- ShellCheck directives: `# shellcheck source=helpers.sh` before sourcing; `-e SC1091` suppresses sourcing warnings globally
- All new scripts must be executable (`chmod +x`)
- Graceful fallbacks: every optional tool (`fd`, `bat`, `rg`, `zoxide`) has a fallback path — maintain this pattern
- tmux options use the `@dispatch-` prefix
