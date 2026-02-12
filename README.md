# tmux-ferret

[![CI](https://github.com/ZviBaratz/tmux-ferret/actions/workflows/ci.yml/badge.svg)](https://github.com/ZviBaratz/tmux-ferret/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Fuzzy file finder, live content search, and session picker as tmux popups. Switch between modes mid-session, edit files in the popup, manage sessions, or send commands to your working pane.

<!-- Demo GIF: record with `vhs demo.tape` (requires https://github.com/charmbracelet/vhs) -->
<!-- TODO: embed demo.gif once recorded -->

## Features

- **File finder** — `fd`/`find` with `bat` preview, instant filtering
- **Live grep** — Ripgrep reloads on every keystroke with line-highlighted preview
- **Session picker** — Switch, create, or kill tmux sessions with window grid preview
- **Mode switching** — `Ctrl+G`/`Ctrl+F` toggles between file and grep mode (query preserved), `Ctrl+W` jumps to sessions
- **Text prefix switching** — Type `>` in file mode to jump to grep, `@` from file/grep to jump to sessions (VSCode command palette style)
- **Project launcher** — `Ctrl+N` in session mode to create sessions from project directories
- **Dual-action editing** — `Enter` edits in the popup, `Ctrl+O` sends `$EDITOR file` to your pane
- **Multi-select** — `Tab`/`Shift+Tab` in file mode to select multiple files, open or copy them all at once
- **Clipboard** — `Ctrl+Y` copies file path(s) or session name to system clipboard via tmux
- **Editor-agnostic** — Popup uses vim/nvim, send-to-pane uses `$EDITOR` (VS Code, Cursor, etc.)
- **Graceful fallbacks** — Works without `fd` (uses `find`), without `bat` (uses `head`)
- **tmux < 3.2 support** — Falls back to `split-window` when `display-popup` isn't available

## Requirements

- **tmux** 2.6+ (3.2+ recommended for popup support)
- **fzf** (0.38+ recommended for mode switching; core features work with older versions)
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

## Default Keybindings

| Key | Mode | Description |
|-----|------|-------------|
| `Alt+o` | prefix-free | Open file finder popup |
| `Alt+s` | prefix-free | Open live grep popup |
| `Alt+w` | prefix-free | Open session picker popup |
| `prefix+e` | prefix | Open file finder popup |

### Inside the popup — files & grep

| Key | Action |
|-----|--------|
| `Enter` | Edit file in popup (vim/nvim) |
| `Ctrl+O` | Send editor open command to originating pane |
| `Ctrl+Y` | Copy file path to clipboard |
| `Tab` / `Shift+Tab` | Toggle selection (file mode, multi-select) |
| `Ctrl+G` | Switch to grep mode (from file mode) |
| `Ctrl+F` | Switch to file mode (from grep mode) |
| `Ctrl+W` | Switch to session picker |
| `>` prefix | Type `>` as first character in file mode → switch to grep |
| `@` prefix | Type `@` as first character → switch to sessions |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

### Inside the popup — sessions

| Key | Action |
|-----|--------|
| `Enter` | Switch to selected session, or create if name is new |
| `Ctrl+K` | Kill selected session (refuses to kill current) |
| `Ctrl+N` | Create session from project directory |
| `Ctrl+Y` | Copy session name to clipboard |
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

The plugin uses a single unified script (`scripts/ferret.sh`) with a `--mode` flag. fzf's [`become`](https://junegunn.github.io/fzf/reference/#action) action enables seamless mode switching — when you press `Ctrl+G` in file mode, fzf replaces itself with a new instance in grep mode, preserving your query.

```
ferret.sh --mode=files
  ├── fd | fzf (filtering enabled)
  │   ├── Ctrl+G → become(ferret.sh --mode=grep --query={q})
  │   ├── Ctrl+W → become(ferret.sh --mode=sessions)
  │   ├── ">" prefix → become(ferret.sh --mode=grep --query={q})
  │   └── "@" prefix → become(ferret.sh --mode=sessions)
  │
ferret.sh --mode=grep
  ├── fzf --disabled + change:reload:rg (live search)
  │   ├── Ctrl+F → become(ferret.sh --mode=files --query={q})
  │   ├── Ctrl+W → become(ferret.sh --mode=sessions)
  │   └── "@" prefix → become(ferret.sh --mode=sessions)
  │
ferret.sh --mode=sessions
  ├── tmux list-sessions | fzf (session picker + creator)
  │   └── Ctrl+N → become(ferret.sh --mode=session-new)
  │
ferret.sh --mode=session-new
  └── fd directories | fzf (project directory picker)
```

## Troubleshooting

**Alt keys not working** — Your terminal emulator must send Alt as Meta (Escape prefix). In iTerm2: Profiles → Keys → Left Option key → Esc+. In Alacritty/Kitty this is the default.

**"ripgrep (rg) is required"** — Grep mode needs ripgrep installed. Install with `apt install ripgrep`, `brew install ripgrep`, or `mise use -g ripgrep@latest`.

**Popup not appearing** — tmux < 3.2 doesn't support `display-popup`. The plugin falls back to `split-window` automatically, which opens a pane instead of a floating popup. Upgrade tmux for the popup experience.

**"unknown action: become"** — Mode switching (`Ctrl+G`/`Ctrl+F`) requires fzf 0.38+. Upgrade fzf to use this feature. File finding and grep work without it — you just can't switch between modes.

**Filenames with colons** — Grep mode parses `file:line:content` using colon as a delimiter. Files with `:` in the name (rare on Unix, impossible on Windows) will not be handled correctly. This is a known limitation shared by virtually all fzf+rg workflows.

## License

MIT
