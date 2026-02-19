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
- **fzf 0.38+** (0.45+ for dynamic labels, 0.49+ for all features)
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

## Your First Keybinding

After installing, one keybinding works immediately with no configuration:

| Key | What it does |
|-----|-------------|
| `Alt+o` | Open the file finder (the unified entry point) |

All modes are accessible from here by typing a prefix character. No additional keybindings are configured by default — all others are opt-in via `@dispatch-*` options.

> **Tip:** If `Alt+o` doesn't work in your terminal, see the [FAQ](faq#alt-key-alto-doesnt-work) or use the prefix keybinding `prefix + e` instead.

## First Steps Tutorial

### 1. Open a tmux session in any project directory

If you don't have one already:

```bash
tmux new-session -s myproject -c ~/my-project
```

### 2. Launch the file finder

Press `Alt+o`. The file finder popup appears with a cheat sheet in the preview panel showing all available keybindings and mode prefixes. Press `?` at any time in any mode to see context-sensitive help for the current mode.

### 3. Search and preview files

Start typing to filter files -- the file list narrows instantly as you type. Navigate with arrow keys and the preview panel updates in real-time with syntax-highlighted file content.

### 4. Open a file

- Press `Enter` to open the selected file in the popup editor (vim/nvim)
- Press `Ctrl+O` to send the editor command to your originating pane (useful for GUI editors like VS Code)

### 5. Bookmark a file

Navigate to a file you use often and press `Ctrl+B` to bookmark it. Bookmarked files are marked with a star (★) and always appear at the top of the file list, regardless of search query. Press `Ctrl+B` again to remove the bookmark.

### 6. Open in your pane (non-vim editors)

Press `Ctrl+O` instead of `Enter` to send the editor command to your originating tmux pane rather than opening inside the popup. This is especially useful for GUI editors like VS Code -- configure it with:

```tmux
set -g @dispatch-pane-editor 'code'
```

See the [FAQ](faq#how-do-i-use-vs-code-or-another-non-vim-editor) for more details on editor configuration.

### 7. Try mode switching

From the file finder, type a prefix character to switch to a different mode. The remainder of your typed text becomes the query in the new mode:

- Need to find where a function is defined? Type `>` to switch to grep -- for example, `>useState` searches for "useState" across all files
- Want to jump to another project? Type `@` to switch to sessions -- for example, `@api` filters sessions containing "api"
- Curious what you've changed? Type `!` to switch to git status and see changed files
- Need to work in a different directory? Type `#` to switch to directories and jump to a different directory

### 8. Return home

In any sub-mode, press backspace on an empty query to return to the file finder. This creates a natural navigation pattern: jump into a mode, do what you need, backspace to return.

## Next Steps

- [Modes overview](modes/) -- detailed documentation for each mode (files, grep, git, directories, sessions, windows)
- [Configuration](reference/configuration) -- customize keybindings, editors, popup size, and search tool options
- [Keybindings Reference](reference/keybindings) -- the complete keybinding table for every mode

### Common Customizations

Here are some popular configuration tweaks to add to your `~/.tmux.conf`:

```tmux
# Make the popup bigger (default: 85%)
set -g @dispatch-popup-size '95%'

# Use VS Code for Ctrl+O (send-to-pane)
set -g @dispatch-pane-editor 'code'

# Disable frecency ranking (always show alphabetical order)
set -g @dispatch-history 'off'

# Limit fd search depth for large repos
set -g @dispatch-fd-args '--max-depth 5'
```
