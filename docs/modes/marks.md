---
title: Marks
parent: Modes
nav_order: 9
---
# Marks (Global Bookmarks)

Marks mode shows all your bookmarked files from every directory in one place. Unlike the per-directory bookmarks shown in files mode (where bookmarked files get a gold star and float to the top), marks mode aggregates bookmarks across your entire filesystem and displays them as tilde-collapsed absolute paths.

This is useful for jumping to frequently-used files across projects -- configuration files, key source files, or any file you've bookmarked from any directory.

## How to access

- Press `Ctrl+G` from files mode.

## Keybindings

| Key | Action |
|-----|--------|
| `Enter` | Open file in popup editor (cds to file's directory) |
| `Ctrl+O` | Send file path to originating pane |
| `Ctrl+Y` | Copy absolute path to clipboard |
| `Ctrl+B` | Remove bookmark (unbookmark with list reload) |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `?` | Show help cheat sheet in preview |
| `Escape` | Close popup |

## Features

- **Cross-project view** -- aggregates bookmarks from all directories, not just the current one.
- **Tilde-collapsed paths** -- displays `~/Projects/api/routes.ts` instead of `/home/user/Projects/api/routes.ts`.
- **File existence checking** -- automatically hides bookmarks pointing to deleted files.
- **Deduplication** -- if the same file is bookmarked from multiple contexts, it appears once.
- **Preview** -- syntax-highlighted file preview via bat (with head fallback).
- **Directory-aware editing** -- when you open a file from marks, the editor starts in that file's directory, so LSP and relative imports work correctly.

## Tips

- Bookmark your most-used config files (`~/.tmux.conf`, `~/.zshrc`, etc.) from their directories, then use `Ctrl+G` to jump to them from any project.
- Marks mode works alongside per-directory bookmarks. Files you bookmark with `Ctrl+B` in files mode appear both in the local bookmark list (with the star indicator) and in the global marks view.
- If a bookmarked file no longer exists (e.g., after deleting or moving it), it won't appear in marks. Use `Ctrl+B` to clean up stale entries.
