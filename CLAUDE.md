# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

tmux-fzf-finder is a tmux plugin (installed via TPM) that provides fuzzy file finding and live grep search in tmux popups. Written entirely in bash.

## Commands

### Lint (matches CI)
```bash
shellcheck -x -e SC1091 fzf-finder.tmux scripts/*.sh
```

### Syntax check
```bash
bash -n fzf-finder.tmux && bash -n scripts/helpers.sh && bash -n scripts/finder.sh && bash -n scripts/preview.sh
```

### Manual testing
Requires a running tmux session. Reload the plugin with:
```bash
tmux source-file ~/.tmux.conf
```

## Architecture

Four shell scripts, no build step:

- **`fzf-finder.tmux`** — TPM entry point. Reads `@finder-*` tmux options and registers keybindings. Detects tmux version to choose between `display-popup` (3.2+) and `split-window` fallback.
- **`scripts/helpers.sh`** — Sourced by all other scripts. Provides `get_tmux_option` and tool detection functions (`detect_fd`, `detect_bat`, `detect_rg`, `detect_popup_editor`, `detect_pane_editor`). Handles Debian/Ubuntu renamed binaries (e.g., `fdfind`, `batcat`).
- **`scripts/finder.sh`** — Main script dispatched in two modes via `--mode=files|grep`. Uses fzf's `become` action to switch modes mid-session while preserving the query. Handles all user actions (edit in popup, send to pane, clipboard copy).
- **`scripts/preview.sh`** — Called by fzf as the preview command in grep mode. Shows file content with line highlighting via bat (or head fallback).

## Conventions

- All scripts use `#!/usr/bin/env bash`; `finder.sh` and `preview.sh` use `set -euo pipefail`
- ShellCheck directives: `# shellcheck source=helpers.sh` before sourcing; `-e SC1091` suppresses sourcing warnings globally
- All new scripts must be executable (`chmod +x`)
- Graceful fallbacks: every optional tool (`fd`, `bat`, `rg`) has a fallback path — maintain this pattern
- tmux options use the `@finder-` prefix
