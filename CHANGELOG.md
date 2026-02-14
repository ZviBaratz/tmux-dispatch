# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Recently opened files appear first in file finder

## [1.0.0] - 2026-02-12

### Added
- File finder mode with `fd`/`find` and `bat` preview
- Live grep mode with ripgrep and line-highlighted preview
- Session picker/creator with window grid preview
- Mode switching via text prefixes: `>` for grep, `@` for sessions, backspace for home (requires fzf 0.38+)
- Project launcher via `Ctrl+N` in session mode
- Dual-action editing: popup editor and send-to-pane
- Multi-select in file mode with `Tab`/`Shift+Tab`
- Clipboard support via `Ctrl+Y`
- Configurable keybindings, popup size, and editor preferences
- Graceful fallbacks for `fd`, `bat`, and `rg`
- tmux < 3.2 support via `split-window` fallback
- CI pipeline with ShellCheck, syntax checking, and bats tests

[Unreleased]: https://github.com/ZviBaratz/tmux-dispatch/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ZviBaratz/tmux-dispatch/releases/tag/v1.0.0
