---
title: Scrollback Search
parent: Modes
nav_order: 7
---
# Scrollback Search

Scrollback search mode lets you search through your terminal's scrollback buffer -- the text that has scrolled off the top of your tmux pane. It captures the scrollback history from the pane where you invoked the popup, deduplicates and reverse-orders the lines, and presents them in fzf for fuzzy searching. The preview pane shows surrounding context for each match.

This is useful for grabbing a command you ran earlier, copying a file path from build output, or finding an error message that scrolled past. Instead of manually scrolling up through your terminal, you get instant fuzzy search with context preview.

## How to access

- Type `$` from files mode -- the remainder of your query becomes the search term.

## Keybindings

| Key | Action |
|-----|--------|
| `Enter` | Copy selected line(s) to tmux buffer + system clipboard |
| `Ctrl+O` | Paste selection into originating pane |
| `Tab` / `Shift+Tab` | Toggle selection (multi-select) |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `?` | Show help cheat sheet in preview |
| `Escape` | Close popup |

## Features

- **Deduplication** -- duplicate lines are removed so you see each unique line only once, even if it appeared many times in your scrollback.
- **Reverse order** -- the most recent lines appear first, so the output you just saw is at the top of the list.
- **Context preview** -- the preview pane shows the selected line in context, with surrounding lines from the scrollback buffer, so you can see what came before and after.
- **Multi-select** -- use `Tab` and `Shift+Tab` to select multiple lines before copying or pasting. All selected lines are included in the copy/paste operation.
- **Clipboard copy** -- `Enter` copies the selected line(s) to both the tmux paste buffer and the system clipboard.
- **Pane paste** -- `Ctrl+O` sends the selected text directly to the originating pane, useful for re-running a command or pasting a path.

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-scrollback-lines` | `10000` | Number of scrollback lines to capture from the originating pane |

## Tips

- The number of captured lines is configurable via `@dispatch-scrollback-lines`. Increase it if you frequently need to search further back, or decrease it for faster startup on slower machines.
- From files mode, type `$error` to instantly search your scrollback for "error" -- the `$` switches to scrollback and `error` becomes the query.
- Multi-select is especially useful for copying multiple related lines (e.g., a multi-line stack trace or a sequence of commands).
- Scrollback search captures text from the pane where you opened the popup, not all panes. If you need text from a different pane, switch to that pane first.
