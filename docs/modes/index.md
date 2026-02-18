---
title: Modes
nav_order: 3
has_children: true
---

# Modes

Modes are the core concept in tmux-dispatch. Each mode gives you a different way to interact with your tmux environment — finding files, searching content, managing sessions, and more — all from a single popup that stays open as you work.

**Files** is the home mode. You start here every time you open the popup. From files, type a prefix character to jump to any other mode. Backspace on an empty query returns you home. This creates a natural hub-and-spoke pattern: start at files, jump to what you need, come back when you're done.

## Mode Overview

| Mode | Prefix | Description | When to use it |
|------|--------|-------------|----------------|
| [File Finder](files) | _(home)_ | Fuzzy file search with `bat` preview, bookmarks, frecency ranking, and git status indicators | You want to quickly open, preview, or manage any file in your project |
| [Live Grep](grep) | `>` | Ripgrep reloads on every keystroke with line-highlighted preview | You need to find where a function is defined or search for a specific string |
| [Git Status](git) | `!` | Stage/unstage files with `Tab`, colored status icons, inline diff preview | You want to review changes, stage files, or check what you've modified |
| [Directories](dirs) | `#` | Jump to directories via zoxide frecency or `fd`/`find` fallback | You need to `cd` into a project directory or recent folder |
| [Sessions](sessions) | `@` | Switch, create, rename, or kill tmux sessions with window grid preview | You want to jump between projects or spin up a new workspace |
| [Windows](windows) | _(from sessions)_ | Browse windows within a session using 2D grid navigation with pane content preview | You want to see what's running in each window before switching |

## How Mode Switching Works

Mode switching uses prefix characters — special characters that, when typed as the first character in the query, switch you to a different mode:

- Type `>` to switch to grep — the rest of your query becomes the search term (e.g., `>useState` searches for "useState")
- Type `@` to switch to sessions — filter sessions by name (e.g., `@api` shows sessions containing "api")
- Type `!` to switch to git status — see your uncommitted changes
- Type `#` to switch to directories — jump to a recent or nearby directory

In any sub-mode, press **Backspace** on an empty query to return to the file finder. This works like VSCode's command palette — you never need to close and reopen the popup.

Windows mode is accessed from sessions mode by pressing `Ctrl+W` on a session, and returns to sessions with Backspace.

See [Mode Switching](../features/mode-switching) for the full details on prefix-based navigation.
