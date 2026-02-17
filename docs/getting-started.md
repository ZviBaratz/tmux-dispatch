---
title: Getting Started
nav_order: 2
---

# Getting Started

This guide walks you through installing tmux-dispatch, setting up dependencies, and using the plugin for the first time.

## Installation

### Via TPM (recommended)

Add to your `~/.tmux.conf`:

```tmux
set -g @plugin 'ZviBaratz/tmux-dispatch'
```

Then press `prefix + I` to install. TPM will clone the repository and source the plugin automatically.

### Manual

Clone the repository into your tmux plugins directory:

```bash
git clone https://github.com/ZviBaratz/tmux-dispatch.git ~/.tmux/plugins/tmux-dispatch
```

Add to your `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-dispatch/dispatch.tmux
```

Then reload your tmux configuration:

```bash
tmux source-file ~/.tmux.conf
```

## Dependencies

### Required

- **tmux 2.6+** (3.2+ recommended for popup support; older versions fall back to `split-window`)
- **bash 4.0+** (macOS ships bash 3.2 -- install a newer version via Homebrew)
- **fzf 0.38+** (0.49+ recommended for all features including dynamic labels)
- **perl** (used by session and window preview rendering)

### Optional (but recommended)

- **fd** -- faster file finding with smart defaults (fallback: `find`)
- **bat** -- syntax-highlighted file preview (fallback: `head`)
- **rg** (ripgrep) -- **required** for grep mode (no fallback)
- **zoxide** -- frecency-ranked directories for directory jump mode

### Install commands by platform

**macOS (Homebrew):**

```bash
brew install bash fzf fd bat ripgrep zoxide
```

**Ubuntu/Debian:**

```bash
sudo apt install fzf fd-find bat ripgrep
# zoxide: install via cargo or the official installer
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
```

Note: On Ubuntu/Debian, `fd` is installed as `fdfind` and `bat` is installed as `batcat`. tmux-dispatch detects these renamed binaries automatically.

**Arch Linux:**

```bash
sudo pacman -S fzf fd bat ripgrep zoxide
```

**Fedora:**

```bash
sudo dnf install fzf fd-find bat ripgrep
# zoxide: install via cargo or the official installer
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
```

## Your First 3 Keybindings

After installing, these keybindings work immediately with no configuration:

| Key | What it does |
|-----|-------------|
| `Alt+o` | Open the file finder |
| `Alt+s` | Open live grep |
| `Alt+w` | Open session picker |

All keybindings are prefix-free -- you don't need to press the tmux prefix first.

## First Steps Tutorial

### 1. Open a tmux session in any project directory

If you don't have one already:

```bash
tmux new-session -s myproject -c ~/my-project
```

### 2. Launch the file finder

Press `Alt+o`. The file finder popup appears with a cheat sheet in the preview panel showing all available keybindings and mode prefixes.

### 3. Search and preview files

Start typing to filter files -- the file list narrows instantly as you type. Navigate with arrow keys and the preview panel updates in real-time with syntax-highlighted file content.

### 4. Open a file

- Press `Enter` to open the selected file in the popup editor (vim/nvim)
- Press `Ctrl+O` to send the editor command to your originating pane (useful for GUI editors like VS Code)

### 5. Try mode switching

From the file finder, type a prefix character to switch to a different mode. The remainder of your typed text becomes the query in the new mode:

- Type `>` to switch to grep -- for example, `>useState` searches for "useState" across all files
- Type `@` to switch to sessions -- for example, `@api` filters sessions containing "api"
- Type `!` to switch to git status and see changed files
- Type `#` to switch to directories and jump to a different directory

### 6. Return home

In any sub-mode, press backspace on an empty query to return to the file finder. This creates a natural navigation pattern: jump into a mode, do what you need, backspace to return.

## Next Steps

- [Modes overview](modes/) -- detailed documentation for each mode (files, grep, git, directories, sessions, windows)
- [Configuration](reference/configuration) -- customize keybindings, editors, popup size, and search tool options
- [Keybindings Reference](reference/keybindings) -- the complete keybinding table for every mode
