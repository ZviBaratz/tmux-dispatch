<p align="center">
  <img src="assets/banner.png" alt="tmux-dispatch" width="800">
</p>

<p align="center">
  <a href="https://github.com/ZviBaratz/tmux-dispatch/actions/workflows/ci.yml"><img src="https://github.com/ZviBaratz/tmux-dispatch/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/tmux/tmux"><img src="https://img.shields.io/badge/tmux-2.6+-1BB91F?logo=tmux" alt="tmux"></a>
</p>

<h3 align="center">A unified command palette for tmux — files, grep, git, directories, and sessions in one popup.</h3>

<p align="center">
  <img src="assets/demo.gif" alt="tmux-dispatch demo" width="800">
</p>

<!-- Re-record: vhs demo.tape (requires https://github.com/charmbracelet/vhs) -->

## Features

- **File finder** — `fd`/`find` with `bat` preview, instant filtering
- **Live grep** — Ripgrep reloads on every keystroke with line-highlighted preview
- **Git status** — View changed files with colored status icons, stage/unstage with `Tab`
- **Directory jump** — Browse zoxide history (or `fd`/`find` directories), `Enter` sends `cd` to your pane
- **Session picker** — Switch, create, or kill tmux sessions with window grid preview
- **Window picker** — `Ctrl+W` in sessions to browse windows with pane content preview
- **Mode switching** — Type `>` to grep, `@` to sessions, `!` to git, `#` to directories — backspace returns home
- **Bookmarks** — `Ctrl+B` to bookmark files, bookmarked files show ★ and appear first
- **Frecency ranking** — Recently and frequently opened files float to the top (per-directory)
- **File type filters** — Restrict file finder to specific extensions via `@dispatch-file-types`
- **Git status indicators** — Modified/staged/untracked files show colored icons inline
- **In-place actions** — `Ctrl+R` to rename files/sessions, `Ctrl+X` to delete files
- **Project launcher** — `Ctrl+N` in session mode to create sessions from project directories
- **Dual-action editing** — `Enter` edits in the popup, `Ctrl+O` sends `$EDITOR file` to your pane
- **Multi-select** — `Tab`/`Shift+Tab` to select multiple files, open or copy them all at once
- **Clipboard** — `Ctrl+Y` copies file path(s), `file:line` in grep, or session name to clipboard
- **Editor-agnostic** — Popup uses vim/nvim, send-to-pane uses `$EDITOR` (VS Code, Cursor, etc.)
- **Graceful fallbacks** — Works without `fd` (uses `find`), without `bat` (uses `head`), without popups (uses split-window)

## Quick Start

After installing, these keybindings are immediately available:

- **`Alt+o`** — Find files in the current directory
- **`Alt+s`** — Live grep (search file contents)
- **`Alt+w`** — Switch or create tmux sessions

Type `>` to switch to grep, `@` to sessions, `!` to git status, `#` to directories. Backspace on empty returns home to files — just like VSCode's command palette.

## Installation

### Via [TPM](https://github.com/tmux-plugins/tpm)

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'ZviBaratz/tmux-dispatch'
```

Then press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/ZviBaratz/tmux-dispatch.git ~/.tmux/plugins/tmux-dispatch
```

Add to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-dispatch/dispatch.tmux
```

<details>
<summary><strong>Dependencies</strong></summary>

- **tmux** 2.6+ (3.2+ recommended for popup support)
- **bash** 4.0+ (macOS users: install via `brew install bash` — the default `/bin/bash` is 3.2)
- **fzf** 0.38+ (0.49+ recommended for all features; core file/grep works with older versions)
- **perl** (required for session preview rendering)
- **Optional:** `fd` (faster file finding), `bat` (syntax-highlighted preview), `rg` (required for grep mode), `zoxide` (frecency-ranked directories for `#` mode)

```bash
# macOS (Homebrew)
brew install bash fzf fd bat ripgrep

# Ubuntu / Debian
sudo apt install fzf fd-find bat ripgrep

# Arch Linux
pacman -S fzf fd bat ripgrep

# Fedora
sudo dnf install fzf fd-find bat ripgrep
```

</details>

---

<details>
<summary><strong>Keybindings Reference</strong></summary>

### Global tmux keybindings

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
| `Ctrl+B` | Toggle bookmark (★ indicator, pinned to top) |
| `Ctrl+R` | Rename file |
| `Ctrl+X` | Delete file(s) (multi-select supported) |
| `Tab` / `Shift+Tab` | Toggle selection (multi-select) |
| `>` prefix | Switch to grep (remainder becomes query) |
| `@` prefix | Switch to sessions (remainder becomes query) |
| `!` prefix | Switch to git status (remainder becomes query) |
| `#` prefix | Switch to directories (remainder becomes query) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

### Inside the popup — grep

| Key | Action |
|-----|--------|
| `Enter` | Edit file at matching line in popup |
| `Ctrl+O` | Send editor open command to originating pane |
| `Ctrl+Y` | Copy `file:line` to clipboard |
| `Ctrl+R` | Rename file |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

### Inside the popup — git status

| Key | Action |
|-----|--------|
| `Enter` | Edit file in popup |
| `Tab` | Stage/unstage file |
| `Ctrl+O` | Send editor open command to originating pane |
| `Ctrl+Y` | Copy file path to clipboard |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

### Inside the popup — directories

| Key | Action |
|-----|--------|
| `Enter` | Send `cd` command to originating pane |
| `Ctrl+Y` | Copy directory path to clipboard |
| `Backspace` on empty | Return to files (home) |
| `Ctrl+D` / `Ctrl+U` | Scroll preview down/up |
| `Escape` | Close popup |

### Inside the popup — sessions

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

</details>

<details>
<summary><strong>Configuration</strong></summary>

All options are set via tmux options in `~/.tmux.conf`:

```tmux
# Change keybindings (set to "none" to disable)
set -g @dispatch-find-key "M-o"              # default: M-o (Alt+o)
set -g @dispatch-grep-key "M-s"              # default: M-s (Alt+s)
set -g @dispatch-session-key "M-w"           # default: M-w (Alt+w)
set -g @dispatch-git-key "none"              # default: none (use ! prefix instead)
set -g @dispatch-prefix-key "e"              # default: e (prefix+e)
set -g @dispatch-session-prefix-key "none"   # default: none

# Popup size
set -g @dispatch-popup-size "85%"            # default: 85%

# Editors
set -g @dispatch-popup-editor "nvim"         # default: auto-detect (nvim > vim > vi)
set -g @dispatch-pane-editor "code"          # default: $EDITOR or auto-detect

# Extra arguments for search tools
set -g @dispatch-fd-args "--max-depth 8"
set -g @dispatch-rg-args "--glob '!*.min.js'"

# Recently opened files appear first in file finder
set -g @dispatch-history "off"               # default: on

# Git status indicators in file finder (colored icons for modified/staged/untracked)
set -g @dispatch-git-indicators "off"        # default: on

# Restrict file finder to specific extensions (comma-separated)
set -g @dispatch-file-types "ts,tsx,js"      # default: "" (all files)

# Session mode: directories for Ctrl+N project picker (colon-separated)
set -g @dispatch-session-dirs "$HOME/Projects:$HOME/work"
```

</details>

<details>
<summary><strong>How It Works</strong></summary>

The plugin uses a single unified script (`scripts/dispatch.sh`) with a `--mode` flag. fzf's [`become`](https://junegunn.github.io/fzf/reference/#action) action enables seamless mode switching — VSCode command palette style, where files is the home mode, prefixes step into sub-modes, and backspace returns home.

```
dispatch.sh --mode=files  (home mode, prompt: "  ")
  ├── fd | fzf (filtering, bookmarks ★, git indicators, frecency ranking)
  │   ├── ">" prefix → become(dispatch.sh --mode=grep --query={q})
  │   ├── "@" prefix → become(dispatch.sh --mode=sessions --query={q})
  │   ├── "!" prefix → become(dispatch.sh --mode=git --query={q})
  │   └── "#" prefix → become(dispatch.sh --mode=dirs --query={q})
  │
dispatch.sh --mode=grep  (prompt: "> ")
  ├── fzf --disabled + change:reload:rg (live search)
  │   └── ⌫ on empty → become(dispatch.sh --mode=files)
  │
dispatch.sh --mode=git  (prompt: "! ")
  ├── git status --porcelain | fzf (stage/unstage with Tab, diff preview)
  │   └── ⌫ on empty → become(dispatch.sh --mode=files)
  │
dispatch.sh --mode=dirs  (prompt: "# ")
  ├── zoxide/fd/find directories | fzf (tree preview, cd on Enter)
  │   └── ⌫ on empty → become(dispatch.sh --mode=files)
  │
dispatch.sh --mode=sessions  (prompt: "@ ")
  ├── tmux list-sessions | fzf (session picker + creator)
  │   ├── ⌫ on empty → become(dispatch.sh --mode=files)
  │   ├── Ctrl+N → become(dispatch.sh --mode=session-new)
  │   └── Ctrl+W → become(dispatch.sh --mode=windows --session={1})
  │
dispatch.sh --mode=session-new
  └── fd directories | fzf (project directory picker)
```

</details>

<details>
<summary><strong>Troubleshooting</strong></summary>

**Alt keys not working** — Your terminal emulator must send Alt as Meta (Escape prefix). In iTerm2: Profiles → Keys → Left Option key → Esc+. In Alacritty/Kitty this is the default.

**"ripgrep (rg) is required"** — Grep mode needs ripgrep installed. Install with `apt install ripgrep`, `brew install ripgrep`, or `mise use -g ripgrep@latest`.

**Popup not appearing** — tmux < 3.2 doesn't support `display-popup`. The plugin falls back to `split-window` automatically, which opens a pane instead of a floating popup. Upgrade tmux for the popup experience.

**"unknown action: become"** — Mode switching (prefix-based and backspace-to-home) requires fzf 0.38+. Upgrade fzf to use this feature. File finding and grep work without it — you just can't switch between modes.

**"command not found" for fzf/fd/rg** — tmux runs plugins in a minimal environment that may not include your login shell's PATH. The plugin automatically checks common locations (Homebrew, mise, asdf, Nix, Cargo), but if your tools are installed elsewhere, add this to your `~/.tmux.conf`:

```tmux
set-environment -g PATH "/your/custom/bin:$PATH"
```

**Clipboard not working on WSL** — The `Ctrl+Y` copy uses `tmux load-buffer -w`, which syncs to the system clipboard via tmux's `set-clipboard` option. On WSL, you may need to install [`win32yank`](https://github.com/equalsraf/win32yank) or configure tmux to use `clip.exe`. See the [tmux wiki on clipboard](https://github.com/tmux/tmux/wiki/Clipboard) for details.

**Box-drawing characters garbled** — The session preview uses Unicode box-drawing (┌─│└). If these render as question marks or garbled text, ensure your terminal uses a Unicode-capable font (e.g., any Nerd Font, JetBrains Mono, or Fira Code).

**Filenames with colons** — Grep mode parses `file:line:content` using colon as a delimiter. Files with `:` in the name (rare on Unix, impossible on Windows) will not be handled correctly. This is a known limitation shared by virtually all fzf+rg workflows.

</details>

## Similar Projects

- [sainnhe/tmux-fzf](https://github.com/sainnhe/tmux-fzf) — fzf-based tmux management (sessions, windows, panes, commands). Complementary to tmux-dispatch.
- [wfxr/tmux-fzf-url](https://github.com/wfxr/tmux-fzf-url) — Open URLs from terminal output via fzf
- [junegunn/fzf](https://github.com/junegunn/fzf) — The fuzzy finder that powers tmux-dispatch (includes built-in `fzf-tmux`)

## License

MIT
