---
title: Keybindings
parent: Reference
nav_order: 1
---

# Keybindings

tmux-dispatch provides keybindings at two levels: global tmux keybindings that open the popup, and mode-specific keybindings that work inside the popup.

Some keybindings are universal across all modes:

- **Ctrl+D / Ctrl+U** scrolls the preview pane down and up
- **Escape** closes the popup

## Global tmux keybindings

These keybindings are registered by the plugin and work from any tmux pane.

| Key | Mode | Description |
|-----|------|-------------|
| `Alt+o` | prefix-free | Open file finder popup |
| `Alt+s` | prefix-free | Open live grep popup |
| `Alt+w` | prefix-free | Open session picker popup |
| `prefix+e` | prefix | Open file finder popup |

All of these can be customized or disabled. See [Configuration](configuration) for details.

## Files (home mode)

The default mode when the popup opens. Provides fuzzy file finding with preview.

| Key | Action |
|-----|--------|
| `Enter` | Edit file in popup (vim/nvim) |
| `Ctrl+O` | Send editor open command to originating pane |
| `Ctrl+Y` | Copy file path to clipboard |
| `Ctrl+B` | Toggle bookmark (starred indicator, pinned to top) |
| `Ctrl+R` | Rename file |
| `Ctrl+X` | Delete file(s) (multi-select supported) |
| `Tab` / `Shift+Tab` | Toggle selection (multi-select) |
| `>` prefix | Switch to grep (remainder becomes query) |
| `@` prefix | Switch to sessions (remainder becomes query) |
| `!` prefix | Switch to git status (remainder becomes query) |
| `#` prefix | Switch to directories (remainder becomes query) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

Mode prefix switching works by typing the prefix character as the first character in the query. The rest of the query carries over to the new mode.

## Grep

Live search mode powered by ripgrep. The query reloads search results on every keystroke.

| Key | Action |
|-----|--------|
| `Enter` | Edit file at matching line in popup |
| `Ctrl+O` | Send editor open command to originating pane |
| `Ctrl+Y` | Copy `file:line` to clipboard |
| `Ctrl+R` | Rename file |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

## Git status

Shows files with uncommitted changes. Status icons are colored by change type.

| Key | Action |
|-----|--------|
| `Enter` | Edit file in popup |
| `Tab` | Stage/unstage file |
| `Ctrl+O` | Send editor open command to originating pane |
| `Ctrl+Y` | Copy file path to clipboard |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

## Directories

Browse directories from zoxide history or filesystem. Selecting a directory sends `cd` to your pane.

| Key | Action |
|-----|--------|
| `Enter` | Send `cd` command to originating pane |
| `Ctrl+Y` | Copy directory path to clipboard |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

## Sessions

Manage tmux sessions: switch between them, create new ones, or kill inactive sessions.

| Key | Action |
|-----|--------|
| `Enter` | Switch to selected session, or create if name is new |
| `Ctrl+K` | Kill selected session (refuses to kill current) |
| `Ctrl+N` | Create session from project directory |
| `Ctrl+W` | Browse windows for selected session |
| `Ctrl+Y` | Copy session name to clipboard |
| `Ctrl+R` | Rename session |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

## Windows

Browse and switch between windows in a session. Arrow keys navigate spatially within the 2-column grid preview.

| Key | Action |
|-----|--------|
| `Enter` | Switch to selected window (and its session) |
| `Right` | Move right in grid (next window) |
| `Left` | Move left in grid (previous window) |
| `Down` | Move down in grid (same column, next row) |
| `Up` | Move up in grid (same column, previous row) |
| `Ctrl+N` / `Ctrl+P` | Sequential navigation (one window at a time) |
| `Backspace` on empty | Return to sessions |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |
