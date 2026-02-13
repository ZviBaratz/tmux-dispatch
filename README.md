# tmux-ferret

[![CI](https://github.com/ZviBaratz/tmux-ferret/actions/workflows/ci.yml/badge.svg)](https://github.com/ZviBaratz/tmux-ferret/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![tmux](https://img.shields.io/badge/tmux-2.6+-1BB91F?logo=tmux)](https://github.com/tmux/tmux)

Fuzzy file finder, live content search, and session picker as tmux popups. Switch between modes mid-session, edit files in the popup, manage sessions, or send commands to your working pane.

<!-- Demo GIF: record with `vhs demo.tape` (requires https://github.com/charmbracelet/vhs) -->
<!-- TODO: embed demo.gif once recorded -->

## Features

- **File finder** — `fd`/`find` with `bat` preview, instant filtering
- **Live grep** — Ripgrep reloads on every keystroke with line-highlighted preview
- **Session picker** — Switch, create, or kill tmux sessions with window grid preview
- **Mode switching** — VSCode command palette style: type `>` to grep, `@` to sessions, backspace to return home (files)
- **Project launcher** — `Ctrl+N` in session mode to create sessions from project directories
- **Dual-action editing** — `Enter` edits in the popup, `Ctrl+O` sends `$EDITOR file` to your pane
- **Multi-select** — `Tab`/`Shift+Tab` in file mode to select multiple files, open or copy them all at once
- **Clipboard** — `Ctrl+Y` copies file path(s) or session name to system clipboard via tmux
- **Editor-agnostic** — Popup uses vim/nvim, send-to-pane uses `$EDITOR` (VS Code, Cursor, etc.)
- **Graceful fallbacks** — Works without `fd` (uses `find`), without `bat` (uses `head`)
- **tmux < 3.2 support** — Falls back to `split-window` when `display-popup` isn't available

## Requirements

- **tmux** 2.6+ (3.2+ recommended for popup support)
- **bash** 4.0+ (macOS users: install via `brew install bash` — the default `/bin/bash` is 3.2)
- **fzf** 0.38+ (0.49+ recommended for all features; core file/grep works with older versions)
- **perl** (required for session preview rendering)
- **Optional:** `fd` (faster file finding), `bat` (syntax-highlighted preview), `rg` (required for grep mode)

## Installation

### Via [TPM](https://github.com/tmux-plugins/tpm)

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'ZviBaratz/tmux-ferret'
```

Then press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/ZviBaratz/tmux-ferret.git ~/.tmux/plugins/tmux-ferret
```

Add to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-ferret/ferret.tmux
```

## Quick Start

After installing, these keybindings are immediately available:

- **`Alt+o`** — Find files in the current directory
- **`Alt+s`** — Live grep (search file contents)
- **`Alt+w`** — Switch or create tmux sessions

Type `>` to switch to grep, `@` to switch to sessions. Backspace on empty returns home to files — just like VSCode's command palette.

## Default Keybindings

| Key | Mode | Description |
|-----|------|-------------|
| `Alt+o` | prefix-free | Open file finder popup |
| `Alt+s` | prefix-free | Open live grep popup |
| `Alt+w` | prefix-free | Open session picker popup |
| `prefix+e` | prefix | Open file finder popup |

### Inside the popup — files (home mode)

| Key | Action |
|-----|--------|
| `Enter` | Edit file in popup (vim/nvim) |
| `Ctrl+O` | Send editor open command to originating pane |
| `Ctrl+Y` | Copy file path to clipboard |
| `Tab` / `Shift+Tab` | Toggle selection (multi-select) |
| `>` prefix | Switch to grep (remainder becomes query) |
| `@` prefix | Switch to sessions (remainder becomes query) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

### Inside the popup — grep

| Key | Action |
|-----|--------|
| `Enter` | Edit file at matching line in popup |
| `Ctrl+O` | Send editor open command to originating pane |
| `Ctrl+Y` | Copy file path to clipboard |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

### Inside the popup — sessions

| Key | Action |
|-----|--------|
| `Enter` | Switch to selected session, or create if name is new |
| `Ctrl+K` | Kill selected session (refuses to kill current) |
| `Ctrl+N` | Create session from project directory |
| `Ctrl+Y` | Copy session name to clipboard |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

## Configuration

All options are set via tmux options in `~/.tmux.conf`:

```tmux
# Change keybindings (set to "none" to disable)
set -g @ferret-find-key "M-o"              # default: M-o (Alt+o)
set -g @ferret-grep-key "M-s"              # default: M-s (Alt+s)
set -g @ferret-session-key "M-w"           # default: M-w (Alt+w)
set -g @ferret-prefix-key "e"              # default: e (prefix+e)
set -g @ferret-session-prefix-key "none"   # default: none

# Popup size
set -g @ferret-popup-size "85%"            # default: 85%

# Editors
set -g @ferret-popup-editor "nvim"         # default: auto-detect (nvim > vim > vi)
set -g @ferret-pane-editor "code"          # default: $EDITOR or auto-detect

# Extra arguments for search tools
set -g @ferret-fd-args "--max-depth 8"
set -g @ferret-rg-args "--glob '!*.min.js'"

# Session mode: directories for Ctrl+N project picker (colon-separated)
set -g @ferret-session-dirs "$HOME/Projects:$HOME/work"
```

## How It Works

The plugin uses a single unified script (`scripts/ferret.sh`) with a `--mode` flag. fzf's [`become`](https://junegunn.github.io/fzf/reference/#action) action enables seamless mode switching — VSCode command palette style, where files is the home mode, prefixes step into sub-modes, and backspace returns home.

```
ferret.sh --mode=files  (home mode, prompt: "  ")
  ├── fd | fzf (filtering enabled)
  │   ├── ">" prefix → become(ferret.sh --mode=grep --query={q})
  │   └── "@" prefix → become(ferret.sh --mode=sessions --query={q})
  │
ferret.sh --mode=grep  (prompt: "> ")
  ├── fzf --disabled + change:reload:rg (live search)
  │   └── ⌫ on empty → become(ferret.sh --mode=files)
  │
ferret.sh --mode=sessions  (prompt: "@ ")
  ├── tmux list-sessions | fzf (session picker + creator)
  │   ├── ⌫ on empty → become(ferret.sh --mode=files)
  │   └── Ctrl+N → become(ferret.sh --mode=session-new)
  │
ferret.sh --mode=session-new
  └── fd directories | fzf (project directory picker)
```

## Troubleshooting

**Alt keys not working** — Your terminal emulator must send Alt as Meta (Escape prefix). In iTerm2: Profiles → Keys → Left Option key → Esc+. In Alacritty/Kitty this is the default.

**"ripgrep (rg) is required"** — Grep mode needs ripgrep installed. Install with `apt install ripgrep`, `brew install ripgrep`, or `mise use -g ripgrep@latest`.

**Popup not appearing** — tmux < 3.2 doesn't support `display-popup`. The plugin falls back to `split-window` automatically, which opens a pane instead of a floating popup. Upgrade tmux for the popup experience.

**"unknown action: become"** — Mode switching (prefix-based and backspace-to-home) requires fzf 0.38+. Upgrade fzf to use this feature. File finding and grep work without it — you just can't switch between modes.

**Filenames with colons** — Grep mode parses `file:line:content` using colon as a delimiter. Files with `:` in the name (rare on Unix, impossible on Windows) will not be handled correctly. This is a known limitation shared by virtually all fzf+rg workflows.

## Similar Projects

- [sainnhe/tmux-fzf](https://github.com/sainnhe/tmux-fzf) — fzf-based tmux management (sessions, windows, panes, commands). Complementary to tmux-ferret.
- [wfxr/tmux-fzf-url](https://github.com/wfxr/tmux-fzf-url) — Open URLs from terminal output via fzf
- [junegunn/fzf](https://github.com/junegunn/fzf) — The fuzzy finder that powers tmux-ferret (includes built-in `fzf-tmux`)

## License

MIT
