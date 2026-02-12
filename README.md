# tmux-fzf-finder

Fuzzy file finder and live content search as tmux popups. Switch between modes mid-session, edit files in the popup or send commands to your working pane.

<!-- TODO: demo GIF -->

## Features

- **File finder** — `fd`/`find` with `bat` preview, instant filtering
- **Live grep** — Ripgrep reloads on every keystroke with line-highlighted preview
- **Mode switching** — `Ctrl+G`/`Ctrl+F` toggles between file and grep mode (query preserved)
- **Dual-action editing** — `Enter` edits in the popup, `Ctrl+O` sends `$EDITOR file` to your pane
- **Clipboard** — `Ctrl+Y` copies the file path via OSC 52 (works over SSH)
- **Editor-agnostic** — Popup uses vim/nvim, send-to-pane uses `$EDITOR` (VS Code, Cursor, etc.)
- **Graceful fallbacks** — Works without `fd` (uses `find`), without `bat` (uses `head`)
- **tmux < 3.2 support** — Falls back to `split-window` when `display-popup` isn't available

## Requirements

- **tmux** 2.6+ (3.2+ recommended for popup support)
- **fzf** 0.38+ (for `become` action used in mode switching)
- **Optional:** `fd` (faster file finding), `bat` (syntax-highlighted preview), `rg` (required for grep mode)

## Installation

### Via [TPM](https://github.com/tmux-plugins/tpm)

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'ZviBaratz/tmux-fzf-finder'
```

Then press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/ZviBaratz/tmux-fzf-finder.git ~/.tmux/plugins/tmux-fzf-finder
```

Add to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-fzf-finder/fzf-finder.tmux
```

## Default Keybindings

| Key | Mode | Description |
|-----|------|-------------|
| `Alt+f` | prefix-free | Open file finder popup |
| `Alt+s` | prefix-free | Open live grep popup |
| `prefix+e` | prefix | Open file finder popup |

### Inside the popup

| Key | Action |
|-----|--------|
| `Enter` | Edit file in popup (vim/nvim) |
| `Ctrl+O` | Send `$EDITOR [+line] file` to originating pane |
| `Ctrl+Y` | Copy file path to clipboard (OSC 52) |
| `Ctrl+G` | Switch to grep mode (from file mode) |
| `Ctrl+F` | Switch to file mode (from grep mode) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

## Configuration

All options are set via tmux options in `~/.tmux.conf`:

```tmux
# Change keybindings (set to "none" to disable)
set -g @finder-find-key "M-f"       # default: M-f (Alt+f)
set -g @finder-grep-key "M-s"       # default: M-s (Alt+s)
set -g @finder-prefix-key "e"       # default: e (prefix+e)

# Popup size
set -g @finder-popup-size "85%"     # default: 85%

# Editors
set -g @finder-popup-editor "nvim"  # default: auto-detect (nvim > vim > vi)
set -g @finder-pane-editor "code"   # default: $EDITOR or auto-detect

# Extra arguments for search tools
set -g @finder-fd-args "--max-depth 8"
set -g @finder-rg-args "--glob '!*.min.js'"
```

## How It Works

The plugin uses a single unified script (`scripts/finder.sh`) with a `--mode` flag. fzf's [`become`](https://junegunn.github.io/fzf/reference/#action) action enables seamless mode switching — when you press `Ctrl+G` in file mode, fzf replaces itself with a new instance in grep mode, preserving your query.

```
finder.sh --mode=files
  ├── fd | fzf (filtering enabled)
  │   └── Ctrl+G → become(finder.sh --mode=grep --query={q})
  │
finder.sh --mode=grep
  ├── fzf --disabled + change:reload:rg (live search)
  │   └── Ctrl+F → become(finder.sh --mode=files --query={q})
```

## License

MIT
