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

- **File finder** — `fd`/`find` with `bat` preview, bookmarks (★), frecency ranking, git status indicators
- **Live grep** — Ripgrep reloads on every keystroke with line-highlighted preview
- **Git status** — Colored status icons, stage/unstage with `Tab`, inline diff preview
- **Directory jump** — Browse zoxide history, `Enter` sends `cd` to your pane
- **Session management** — Switch, create, kill sessions with window grid preview; launch projects with `Ctrl+N`
- **Window picker** — Browse windows with pane content preview
- **Mode switching** — Type `>` for grep, `@` for sessions, `!` for git, `#` for directories — backspace returns home
- **In-place actions** — Rename (`Ctrl+R`), delete (`Ctrl+X`), bookmark (`Ctrl+B`), multi-select (`Tab`), clipboard (`Ctrl+Y`)
- **Built-in guide** — Opening the popup shows all keybindings and mode prefixes in the preview panel; start typing to dismiss. Press `?` in any mode for context-sensitive help

## Quick Start

After installing, three keybindings are immediately available:

| Key | Action |
|-----|--------|
| `Alt+o` | Find files in the current directory |
| `Alt+s` | Live grep (search file contents) |
| `Alt+w` | Switch or create tmux sessions |

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

### Dependencies

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

## Documentation

Full documentation is available at **[zvibaratz.github.io/tmux-dispatch](https://zvibaratz.github.io/tmux-dispatch/)**.

| | | |
|---|---|---|
| [File Finder](https://zvibaratz.github.io/tmux-dispatch/modes/files) | [Live Grep](https://zvibaratz.github.io/tmux-dispatch/modes/grep) | [Git Status](https://zvibaratz.github.io/tmux-dispatch/modes/git) |
| [Directories](https://zvibaratz.github.io/tmux-dispatch/modes/dirs) | [Sessions](https://zvibaratz.github.io/tmux-dispatch/modes/sessions) | [Windows](https://zvibaratz.github.io/tmux-dispatch/modes/windows) |
| [Configuration](https://zvibaratz.github.io/tmux-dispatch/reference/configuration) | [Keybindings](https://zvibaratz.github.io/tmux-dispatch/reference/keybindings) | [Troubleshooting](https://zvibaratz.github.io/tmux-dispatch/reference/troubleshooting) |

## How is this different?

Most tmux fuzzy-finder plugins provide a menu of separate tmux operations (sessions, windows, panes, commands) where each action opens a new picker. tmux-dispatch takes a different approach:

- **Unified popup** — Files, grep, git, directories, and sessions all live in a single popup. No closing and reopening for different tasks.
- **No-close mode switching** — Type a prefix character (`>`, `@`, `!`, `#`) to switch modes instantly. Backspace on empty returns home. The popup stays open throughout.
- **Frecency ranking** — Recently and frequently opened files appear first, so your most-used files are always within reach.
- **Inline git staging** — Stage and unstage files with `Tab` directly in the git status view, with an inline diff preview. No need to drop to the command line.
- **Bookmarks** — Pin important files with `Ctrl+B` so they always appear at the top of the file list.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a full list of changes in each release.

## Similar Projects

- [sainnhe/tmux-fzf](https://github.com/sainnhe/tmux-fzf) — fzf-based tmux management (sessions, windows, panes, commands). Complementary to tmux-dispatch.
- [wfxr/tmux-fzf-url](https://github.com/wfxr/tmux-fzf-url) — Open URLs from terminal output via fzf
- [junegunn/fzf](https://github.com/junegunn/fzf) — The fuzzy finder that powers tmux-dispatch (includes built-in `fzf-tmux`)

## License

MIT
