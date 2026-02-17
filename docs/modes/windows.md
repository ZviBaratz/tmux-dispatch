---
title: Windows
parent: Modes
nav_order: 6
---
# Windows

![windows demo](../assets/windows.gif)

Window picker mode shows all windows for a specific session with pane content previews. It's accessed from session mode via `Ctrl+W` and provides a quick way to jump to a specific window.

**How to access:** Press `Ctrl+W` in session mode with a session selected.

**Window list format:** `index: name [*] (N panes)` where `*` marks the active window and N shows the pane count.

## Keybindings

| Key | Action |
|-----|--------|
| `Enter` | Switch to selected window (and its session) |
| `Backspace` on empty | Return to sessions |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

## Features

- **Pane content preview** -- window-preview.sh captures the active pane's content with ANSI colors, strips trailing blank lines, and shows the bottom portion (where prompts and recent output live). Uses the same perl-based ANSI-aware width handling as session-preview.sh. See [Preview System](../features/previews) for details.
- **Header info** -- shows session:index, window name, and pane count.
- **Session+window switch** -- selecting a window switches both to the session and the specific window.

## Configuration

There are no mode-specific configuration options for the window picker.

## Tips

- Use `Ctrl+W` from session mode when you know which session you want but need to find the right window.
- The preview shows the bottom of the pane content (where the prompt usually is), making it easy to identify what's running in each window.
- Backspace returns to session mode, not files -- the navigation chain is files -> sessions -> windows -> sessions -> files.
