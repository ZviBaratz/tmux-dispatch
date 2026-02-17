# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-02-12

### Added

**Modes:**
- File finder mode with `fd`/`find` and `bat` preview
- Live grep mode with ripgrep and line-highlighted preview
- Git status mode with stage/unstage toggle
- Directory jump mode with zoxide integration
- Session picker/creator with window grid preview
- Window picker with 2D grid navigation
- Project launcher via `Ctrl+N` in session mode

**Mode switching:**
- Mode switching via text prefixes: `>` for grep, `@` for sessions, `!` for git, `#` for dirs (requires fzf 0.38+)
- Backspace on empty query returns to file finder

**Editing and actions:**
- Dual-action editing: popup editor and send-to-pane
- Multi-select in file mode with `Tab`/`Shift+Tab`
- Clipboard support via `Ctrl+Y`
- In-place rename and delete actions for files and sessions

**History and bookmarks:**
- Recently opened files appear first in file finder (configurable via `@dispatch-history`)
- Bookmark files with `Ctrl+B` for persistent pinning

**Configuration:**
- Configurable keybindings, popup size, and editor preferences

**Compatibility:**
- Graceful fallbacks for `fd`, `bat`, and `rg`
- PATH augmentation for Homebrew, mise, asdf, Nix, and Cargo
- Bash 4.0+ version guard with clear error message on macOS
- tmux < 3.2 support via `split-window` fallback
- CI pipeline with ShellCheck, syntax checking, and bats tests

[Unreleased]: https://github.com/ZviBaratz/tmux-dispatch/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ZviBaratz/tmux-dispatch/releases/tag/v1.0.0
