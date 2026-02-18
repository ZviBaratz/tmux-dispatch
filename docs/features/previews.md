---
title: Preview System
parent: Features
nav_order: 3
---

# Preview System

Every mode shows a live preview so you can see file content, diffs, or session layouts without opening anything. The preview updates as you navigate the list — what you see is what you'll get.

## What Each Mode Shows

| Mode | Preview content |
|------|----------------|
| **Files** | Syntax-highlighted file content (via `bat`) or first 500 lines (via `head`) |
| **Grep** | File content with the matching line highlighted and context around it |
| **Git** | The appropriate diff for each file's status (staged, unstaged, or combined) |
| **Directories** | Directory listing as a colorized tree (via `tree`) or `ls -la` |
| **Sessions** | 2-column grid of bordered window boxes showing live pane content |
| **Windows** | Same grid as sessions, with the selected window highlighted in cyan |

## Preview Scripts

Under the hood, previews are powered by four specialized scripts with graceful fallbacks when optional tools are missing. The preview panel occupies 60% of the popup width by default.

| Script | Mode(s) | What it shows |
|--------|---------|---------------|
| _(inline bat/head)_ | Files | Syntax-highlighted file content or first 500 lines |
| `preview.sh` | Grep | File content with the matching line highlighted |
| `git-preview.sh` | Git | Diff appropriate to the file's status |
| `session-preview.sh` | Sessions, Windows | 2-column grid of window boxes with pane content (highlights selected window in window mode) |

## File Preview (Files Mode)

The file preview is configured inline in `dispatch.sh` rather than using a separate script:

- With **bat** installed: `bat --color=always --style=numbers --line-range=:500` -- shows the first 500 lines with syntax highlighting and line numbers
- Without bat: `head -500` -- shows the first 500 lines as plain text

When the query is empty and the welcome cheat sheet is active, the preview panel displays the cheat sheet instead of a file preview. As soon as you start typing or navigate the list, the preview switches to showing the selected file's content.

## Grep Preview

`preview.sh` receives the filename and line number from fzf's result format (`file:line:content`):

- With **bat**: `bat --color=always --style=numbers --highlight-line LINE FILE` -- the entire file is displayed with the matching line visually highlighted
- Without bat: `head -n LINE+50 FILE | tail -n 100` -- shows approximately 100 lines centered around the match

Line numbers that are not valid integers default to 1, so the preview still works even when the line number cannot be parsed.

## Git Diff Preview

`git-preview.sh` chooses the appropriate diff command based on the file's status icon:

| Icon | Meaning | Diff command |
|------|---------|-------------|
| **✚** (green) | Staged | `git diff --cached -- FILE` |
| **●** (red) | Modified (unstaged) | `git diff -- FILE` |
| **✹** (purple) | Both staged and unstaged | `git diff HEAD -- FILE` (combined view) |
| **?** (yellow) | Untracked | No diff available -- shows file content instead |

When a diff is available, it is syntax-highlighted via `bat --language=diff` if bat is installed. Without bat, the raw diff output is displayed.

The status icon arrives from fzf with ANSI color codes (e.g., `\033[32m✚\033[0m`). The preview script strips these escape sequences via `sed` before comparing against the expected icon characters.

## Session Preview

`session-preview.sh` renders a choose-tree-style grid showing all windows in the selected session:

- Queries tmux for all windows using `tmux list-windows` with format strings
- Captures each window's active pane content with `tmux capture-pane -e -J` (ANSI colors preserved)
- Renders a 2-column grid of bordered boxes (falls back to 1-column when the terminal is narrow or there is only a single window)
- Active window boxes use bright white borders, inactive windows use dim gray borders
- Pane content is processed by an embedded perl script that handles ANSI-aware width calculation, truncation with ellipsis, and padding to exact dimensions
- The header line shows the session name, window count, and attached status

The grid automatically adapts to the available preview dimensions using the `FZF_PREVIEW_LINES` and `FZF_PREVIEW_COLUMNS` environment variables provided by fzf.

## Window Preview

Window mode reuses `session-preview.sh` with an optional highlight parameter (the selected window index). This renders the same 2-column grid as session mode, but with three-state border coloring:

- **fzf-selected window**: bright cyan borders (`\033[1;36m`) — follows the cursor as you navigate
- **tmux-active window**: bright white borders (`\033[1;37m`) — retains the `*` marker in its label
- **Other windows**: dim gray borders (`\033[38;5;244m` / `\033[38;5;238m`)

When called without a highlight parameter (session mode), the behavior is unchanged — only the tmux-active/inactive two-state logic applies.

## Directory Preview

Directory modes (dirs and session-new) show a directory listing in the preview:

- With **tree** installed: `tree -C -L 2` -- colorized tree view, 2 levels deep
- With **GNU ls**: `ls -la --color=always` -- detailed listing with colors
- With **BSD ls** (macOS): `ls -laG` -- detailed listing with BSD color flag

Directories displayed with a `~` prefix (from zoxide) are expanded back to the full `$HOME` path before being passed to the preview command.

## Scroll Controls

All modes support scrolling the preview panel:

| Key | Action |
|-----|--------|
| `Ctrl+D` | Scroll preview half-page down |
| `Ctrl+U` | Scroll preview half-page up |

These bindings are configured in `build_fzf_base_opts` in `helpers.sh` and apply universally across all modes.

## Configuring Editors

The preview system does not directly control editors, but the editing keybindings (`Enter`, `Ctrl+O`) that work alongside previews are editor-agnostic:

| Option | Controls | Default |
|--------|----------|---------|
| `@dispatch-popup-editor` | `Enter` (opens in popup) | auto-detect: nvim > vim > vi |
| `@dispatch-pane-editor` | `Ctrl+O` (sends to pane) | `$EDITOR` if set, otherwise auto-detect: nvim > vim > vi |

The popup editor must be a terminal-based editor (vim, nvim, vi) since it runs inside the tmux popup. The pane editor can be anything -- VS Code, Cursor, Sublime Text, or any other editor that accepts a filename argument -- since the command is sent to your originating tmux pane.
