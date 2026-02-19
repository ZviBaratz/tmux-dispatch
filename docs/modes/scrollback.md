---
title: Scrollback Search
parent: Modes
nav_order: 7
---
# Scrollback Search

Scrollback mode captures content from your tmux pane's scrollback buffer and presents it in fzf for fuzzy searching. It has two views that you can toggle between with `Ctrl+T`:

- **Lines view** -- deduplicated scrollback lines, most-recent-first. Use this to search for commands, output, or error messages.
- **Tokens view** (extract) -- structured tokens extracted from scrollback: URLs, file paths with line numbers, git commit hashes, IP addresses, UUIDs, and diff paths. Use this to quickly act on specific items from your terminal output.

## How to access

- Type `$` from files mode to open the lines view -- the remainder of your query becomes the search term.
- Type `&` from files mode to open the tokens (extract) view directly.
- Or bind a dedicated key via `@dispatch-extract-key` to open tokens view without going through files mode.

## Keybindings

### Lines view

| Key | Action |
|-----|--------|
| `Enter` | Copy selected line(s) to tmux buffer + system clipboard |
| `Ctrl+O` | Paste selection into originating pane |
| `Ctrl+T` | Switch to tokens (extract) view |
| `Tab` / `Shift+Tab` | Toggle selection (multi-select) |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `?` | Show help cheat sheet in preview |
| `Escape` | Close popup |

### Tokens view (extract)

| Key | Action |
|-----|--------|
| `Enter` | Copy selected token(s) to tmux buffer + system clipboard |
| `Ctrl+O` | Smart open: browser for URLs, editor for file:line, clipboard for others |
| `Ctrl+T` | Switch to lines view |
| `Tab` / `Shift+Tab` | Toggle selection (multi-select) |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+/` | Filter by token type (cycles: all → url → path → ...) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `?` | Show help cheat sheet in preview |
| `Escape` | Close popup |

## Token types

The tokens view extracts seven types of structured data from your scrollback:

| Type | Example | Smart open action |
|------|---------|-------------------|
| `url` | `https://example.com/path` | Open in browser |
| `path` | `src/main.rs:42` or `lib/utils.js:10:5` | Open file at line in editor |
| `file` | `README.md` (bare file, must exist on disk) | Open file in editor |
| `hash` | `abc1234` (7-40 hex chars) | `git show` in pane (or copy) |
| `ip` | `192.168.1.1` or `10.0.0.1:8080` | Copy to clipboard |
| `uuid` | `550e8400-e29b-41d4-a716-446655440000` | Copy to clipboard |
| `diff` | `src/main.rs` (from `+++ b/` lines) | Open file in editor |

## Features

- **Two views, one mode** -- `Ctrl+T` toggles between lines and tokens views without leaving the popup. The prompt, border label, and help overlay update to reflect the active view.
- **Deduplication** -- duplicate lines (or tokens) are removed so you see each unique item only once.
- **Reverse order** -- the most recent items appear first, so the output you just saw is at the top of the list.
- **Context preview** -- the preview pane shows surrounding context from the scrollback buffer for both views.
- **Multi-select** -- use `Tab` and `Shift+Tab` to select multiple items before copying or acting.
- **Smart open** -- `Ctrl+O` in tokens view dispatches to the right action based on token type: browser for URLs, editor at line for file paths, clipboard for everything else.
- **ANSI stripping** -- escape codes are stripped before token extraction, so colored terminal output doesn't break regex matching.
- **Configurable default view** -- set `@dispatch-scrollback-view` to `tokens` to land in tokens view by default.
- **Browser detection** -- URL opening uses `$BROWSER` if set, then tries `xdg-open` (Linux) or `open` (macOS). If no browser is found, the URL is copied to the clipboard instead.

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-scrollback-lines` | `10000` | Number of scrollback lines to capture from the originating pane |
| `@dispatch-scrollback-view` | `lines` | Default view when entering scrollback mode: `lines` or `tokens` |
| `@dispatch-extract-key` | `none` | Prefix-free key to open scrollback directly in tokens view (disabled by default) |

## Tips

- The number of captured lines is configurable via `@dispatch-scrollback-lines`. Increase it if you frequently need to search further back, or decrease it for faster startup on slower machines.
- From files mode, type `$error` to instantly search your scrollback for "error" -- the `$` switches to scrollback and `error` becomes the query.
- Multi-select is especially useful for copying multiple related lines (e.g., a multi-line stack trace or a sequence of commands).
- Scrollback captures text from the pane where you opened the popup, not all panes. If you need text from a different pane, switch to that pane first.
- Set `@dispatch-extract-key` to a key like `M-u` if you frequently want to jump straight to token extraction without going through files mode first.
- If no tokens are found but scrollback has content, the mode automatically falls back to lines view with a notification.
