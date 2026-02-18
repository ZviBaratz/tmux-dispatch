---
title: URL Extraction
parent: Modes
nav_order: 8
---
# URL Extraction

URL extraction mode captures all URLs from your tmux pane's scrollback buffer and presents them in fzf for fuzzy searching. You can copy URLs to the clipboard or open them directly in your browser. URLs are shown most-recent-first, deduplicated, and with surrounding scrollback context in the preview pane.

This is useful for opening links from build output, CI logs, documentation references, or any URL that appeared in your terminal. Instead of manually selecting and copying URLs from scrollback, you get instant fuzzy search with one-key actions.

## How to access

- Type `&` from files mode -- the remainder of your query becomes the search term.
- Or bind a dedicated key via `@dispatch-url-key` (disabled by default).

## Keybindings

| Key | Action |
|-----|--------|
| `Enter` | Copy selected URL(s) to tmux buffer + system clipboard |
| `Ctrl+O` | Open selected URL(s) in browser |
| `Tab` / `Shift+Tab` | Toggle selection (multi-select) |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `?` | Show help cheat sheet in preview |
| `Escape` | Close popup |

## Features

- **Automatic extraction** -- URLs are extracted from the full scrollback buffer using a regex that matches `http://`, `https://`, and `ftp://` schemes.
- **Trailing punctuation cleanup** -- trailing characters like `.`, `,`, `;`, `:`, `!`, `?`, `)` are stripped from URLs, since these are almost always sentence terminators rather than part of the URL.
- **Most recent first** -- URLs from the bottom of your scrollback (most recent output) appear at the top of the list.
- **Deduplication** -- each unique URL appears only once, even if it was printed multiple times.
- **Context preview** -- the preview pane shows the surrounding lines from the scrollback where the URL appeared, so you can see what the link is about before opening it.
- **Multi-select** -- use `Tab` and `Shift+Tab` to select multiple URLs. All selected URLs are copied or opened together.
- **Browser detection** -- `Ctrl+O` uses `$BROWSER` if set, then tries `xdg-open` (Linux) or `open` (macOS). If no browser is found, the URL is copied to the clipboard instead.

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `@dispatch-url-key` | `none` | Prefix-free key to open URL extraction directly (disabled by default; use `&` prefix instead) |
| `@dispatch-scrollback-lines` | `10000` | Number of scrollback lines to capture (shared with scrollback search mode) |

## Supported URL schemes

- `http://`
- `https://`
- `ftp://`

URLs with ports, query strings, fragments, and paths are all supported. The extraction regex excludes characters that commonly surround URLs in terminal output (`"`, `<`, `>`, `{`, `}`, `|`, `\`, `` ` ``, `[`, `]`) to minimize false positives.

## Tips

- From files mode, type `&github` to instantly search your scrollback URLs for ones containing "github" -- the `&` switches to URL mode and `github` becomes the query.
- Use multi-select (`Tab`) to copy several URLs at once, then paste them all from the tmux buffer.
- The number of captured scrollback lines is controlled by `@dispatch-scrollback-lines`. Increase it if you need to find URLs from further back in your terminal history.
- URL extraction captures text from the pane where you opened the popup. If you need URLs from a different pane, switch to that pane first.
